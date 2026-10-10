defmodule Shroud.Email.BounceHandlerTest do
  use Shroud.DataCase, async: true
  import ExUnit.CaptureLog
  import Shroud.AccountsFixtures
  import Shroud.AliasesFixtures
  import Shroud.EmailFixtures
  import Swoosh.TestAssertions
  use Oban.Testing, repo: Shroud.Repo
  alias Shroud.Email.{BounceHandler, DeliveryMarker}

  setup do
    Sentry.Test.setup_sentry(dedup_events: false)
    user = user_fixture()
    email_alias = alias_fixture(%{user_id: user.id})

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.from(email_alias.address)
      |> Swoosh.Email.to("recipient@example.org")
      |> Swoosh.Email.subject("Private subject")
      |> Swoosh.Email.text_body("Private body")
      |> DeliveryMarker.attach("outgoing", user, email_alias.address, "recipient@example.org")

    %{user: user, email_alias: email_alias, email: email}
  end

  describe "handle_haraka_bounce_report/2" do
    test "archives the report and sends its object path to Sentry" do
      log =
        capture_log(fn ->
          assert :ok =
                   BounceHandler.handle_haraka_bounce_report("test@test.com", "email-contents")
        end)

      assert [upload] = all_enqueued(worker: Shroud.S3.S3UploadJob)
      assert upload.args["content"] == "email-contents"
      assert upload.args["path"] =~ "/bounces/test@test.com-"
      assert log =~ "Received bounce report from Haraka! See #{upload.args["path"]}."
      refute log =~ "email-contents"
      assert [event] = Sentry.Test.pop_sentry_reports()
      assert event.extra == %{s3_path: upload.args["path"]}
    end

    test "handles authenticated Haraka failures with only a basic SMTP status", %{
      email: email,
      email_alias: email_alias,
      user: user
    } do
      report =
        delivery_status_report(email, status: nil, diagnostic: "smtp;550 Mailbox unavailable")

      assert :ok = BounceHandler.handle_haraka_bounce_report(email_alias.address, report)
      assert [job] = all_enqueued(worker: Shroud.Accounts.UserNotifierJob)
      assert {:ok, notification} = perform_job(Shroud.Accounts.UserNotifierJob, job.args)
      assert notification.to == [{"", user.email}]
      assert notification.text_body =~ "The recipient's mail server reported a delivery failure."
      assert notification.text_body =~ "Delivery status: 5.0.0"
      refute notification.text_body =~ "Mailbox unavailable"
      refute notification.html_body =~ "Mailbox unavailable"
      assert [] = Sentry.Test.pop_sentry_reports()

      incoming =
        DeliveryMarker.attach(
          email,
          "incoming",
          user,
          email_alias.address,
          "recipient@example.org"
        )

      report =
        delivery_status_report(incoming, status: nil, diagnostic: "smtp; 450 Delivery timed out")

      assert :ok = BounceHandler.handle_haraka_bounce_report(email_alias.address, report)
      assert [event] = Sentry.Test.pop_sentry_reports()
      assert event.fingerprint == ["shroud-incoming-forwarding-bounce"]
      assert event.tags == %{delivery_status: "4.0.0"}

      assert_enqueued(
        worker: Shroud.S3.S3UploadJob,
        args: %{content: report, path: event.extra.s3_path}
      )
    end

    test "ignores delays, notifies terminal failures, and suppresses repeated reports", %{
      email: email,
      email_alias: email_alias,
      user: user
    } do
      for opts <- [
            [action: "delayed", status: "4.4.1"],
            [action: "delivered", status: "2.0.0"],
            [action: "delayed", status: nil, diagnostic: "smtp;450 Try again later"]
          ] do
        assert :ok =
                 BounceHandler.handle_haraka_bounce_report(
                   email_alias.address,
                   delivery_status_report(email, opts)
                 )

        assert_no_email_sent()
        assert [] = Sentry.Test.pop_sentry_reports()
        refute_enqueued(worker: Shroud.Accounts.UserNotifierJob)
      end

      failed = delivery_status_report(email, status: "4.4.7")
      assert :ok = BounceHandler.handle_haraka_bounce_report(email_alias.address, failed)

      assert_no_email_sent()
      assert [job] = all_enqueued(worker: Shroud.Accounts.UserNotifierJob)
      assert {:ok, _email} = perform_job(Shroud.Accounts.UserNotifierJob, job.args)
      assert_received {:email, notification}
      assert notification.to == [{"", user.email}]
      assert notification.text_body =~ "Delivery attempts ended without reaching the recipient."
      assert notification.text_body =~ "4.4.7"
      assert notification.text_body =~ "recipient@example.org via #{email_alias.address}"
      assert notification.text_body =~ "Subject: Private subject"
      refute notification.text_body =~ "unrelated@example.net"
      refute Map.has_key?(notification.headers, "X-Shroud-Delivery")

      assert [event] = Sentry.Test.pop_sentry_reports()
      assert event.fingerprint == ["shroud-outgoing-delivery-rejection"]
      assert event.tags == %{delivery_status: "4.4.7"}

      assert_enqueued(
        worker: Shroud.S3.S3UploadJob,
        args: %{path: event.extra.s3_path, content: failed}
      )

      assert event.user == %{}
      assert event.breadcrumbs == []

      assert :ok = BounceHandler.handle_haraka_bounce_report(email_alias.address, failed)
      assert_no_email_sent()
      assert [] = Sentry.Test.pop_sentry_reports()

      bounced_notification = delivery_status_report(notification, status: "5.2.2")

      assert :ok =
               BounceHandler.handle_haraka_bounce_report(
                 "noreply@email.shroud.test",
                 bounced_notification
               )

      assert_no_email_sent()
      assert [event] = Sentry.Test.pop_sentry_reports()
      assert event.fingerprint == ["shroud-unclassified-email-bounce"]
      assert [^job] = all_enqueued(worker: Shroud.Accounts.UserNotifierJob)
    end

    test "does not copy a modified original subject into the notification", %{
      email: email,
      email_alias: email_alias
    } do
      data = delivery_status_report(email) |> String.replace("Private subject", "Forged subject")
      assert :ok = BounceHandler.handle_haraka_bounce_report(email_alias.address, data)
      assert [job] = all_enqueued(worker: Shroud.Accounts.UserNotifierJob)
      assert {:ok, _email} = perform_job(Shroud.Accounts.UserNotifierJob, job.args)
      assert_received {:email, notification}
      refute notification.text_body =~ "Forged subject"
      refute notification.text_body =~ "Subject:"
      assert notification.text_body =~ "recipient@example.org"
      refute notification.html_body =~ "Forged subject"
      refute notification.html_body =~ "Subject:"
    end

    test "does not notify for unsigned, tampered, mismatched, or invalid reports", %{
      email: email,
      email_alias: email_alias,
      user: user
    } do
      unsigned = %{email | headers: %{}}
      marker = email.headers["X-Shroud-Delivery"]
      tampered = %{email | headers: %{"X-Shroud-Delivery" => "x" <> marker}}
      other_user = user_fixture()

      wrong_owner =
        DeliveryMarker.attach(
          email,
          "outgoing",
          other_user,
          email_alias.address,
          "recipient@example.org"
        )

      for {to, data} <- [
            {email_alias.address, delivery_status_report(unsigned)},
            {email_alias.address, File.read!("test/support/data/bounce.email")},
            {email_alias.address, delivery_status_report(tampered)},
            {email_alias.address, delivery_status_report(wrong_owner)},
            {"other@email.shroud.test", delivery_status_report(email)},
            {email_alias.address, delivery_status_report(email, recipient: user.email)},
            {email_alias.address, delivery_status_report(email, status: "5.1.1<script>")},
            {email_alias.address, delivery_status_report(email, status: "2.0.0")},
            {email_alias.address,
             delivery_status_report(email, status: nil, diagnostic: "smtp;250 OK")},
            {email_alias.address,
             delivery_status_report(email, status: nil, diagnostic: "smtp;550<script>")},
            {email_alias.address, delivery_status_report(email, status: nil)},
            {email_alias.address, "Content-Type: multipart/report; boundary=broken\r\n\r\nBroken"}
          ] do
        assert :ok = BounceHandler.handle_haraka_bounce_report(to, data)
        assert_no_email_sent()
        assert [event] = Sentry.Test.pop_sentry_reports()
        assert event.fingerprint == ["shroud-unclassified-email-bounce"]

        assert_enqueued(
          worker: Shroud.S3.S3UploadJob,
          args: %{path: event.extra.s3_path, content: data}
        )
      end

      refute_enqueued(worker: Shroud.Accounts.UserNotifierJob)
    end
  end
end
