defmodule Shroud.Email.EmailHandlerTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog
  import Mox

  import Shroud.{AccountsFixtures, AliasesFixtures, EmailFixtures}

  alias Shroud.Email.EmailHandler
  alias Shroud.{Aliases, Util}

  @html_content """
    <html>
      <body>
        <h1>This is HTML content</h1>
        <p>Lorem ipsum</p>
      </body>
    </html>
  """

  setup do
    user = user_fixture(%{status: :active, email: "user@example.com"})
    email_alias = alias_fixture(%{user_id: user.id, address: "alias@shroud.test"})

    %{
      user: user,
      email_alias: email_alias
    }
  end

  describe "perform/1" do
    test "forwards to the correct user", %{user: user, email_alias: email_alias} do
      args = %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          text_email(
            "sender@example.com",
            [email_alias.address],
            "Hello, world",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{email_alias.address, user.email}]

        assert email.from ==
                 {"sender@example.com (via Shroud.email)",
                  "sender_at_example.com_alias@shroud.test"}

        assert is_nil(email.reply_to)
      end)
    end

    test "handles emails to multiple recipients", %{user: user, email_alias: email_alias} do
      args = %{
        from: "sender@example.com",
        to: [email_alias.address, "other@example.com"],
        data:
          text_email(
            "sender@example.com",
            [email_alias.address, "other@example.com"],
            "To multiple recipients",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == user.email
      end)

      refute_email_sent(%{to: "other@example.com"})
    end

    test "handles emails to multiple shroud recipients", %{user: user, email_alias: email_alias} do
      %{id: user_id} = other_user = user_fixture(%{status: :active})
      other_alias = alias_fixture(%{user_id: user_id})

      args = %{
        from: "sender@example.com",
        to: [email_alias.address, other_alias.address],
        data:
          text_email(
            "sender@example.com",
            [email_alias.address, other_alias.address],
            "To multiple recipients",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == user.email
      end)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == other_user.email
      end)
    end

    test "transforms reply-to headers to reply addresses", %{user: user} do
      email_alias = alias_fixture(%{address: "alias@shroud.local", user_id: user.id})

      args = %{
        from: "sender@example.com",
        to: [email_alias.address],
        data:
          text_email(
            "sender@example.com",
            [email_alias.address],
            "Custom reply-to!",
            "Plain text content",
            "Reply-To: custom@example.com"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        assert recipient == user.email

        assert email.reply_to ==
                 {"custom_at_example.com_alias@shroud.test",
                  "custom_at_example.com_alias@shroud.test"}
      end)
    end

    test "handles replies from an alias", %{user: user} do
      args = %{
        from: user.email,
        to: ["recipient_at_example.com_alias@shroud.test"],
        data:
          text_email(
            user.email,
            ["recipient_at_example.com_alias@shroud.test"],
            "To one recipient",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{"recipient@example.com", "recipient@example.com"}]
        assert email.from == {"alias@shroud.test (via Shroud.email)", "alias@shroud.test"}
        assert is_nil(email.reply_to)
      end)
    end

    test "ignores replies from non-users" do
      args = %{
        from: "other@example.com",
        to: ["recipient_at_example.com_alias@shroud.test"],
        data:
          text_email(
            "other@example.com",
            ["recipient_at_example.com_alias@shroud.test"],
            "To one recipient",
            "Plain text content"
          )
      }

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Discarding outgoing email from other@example.com to recipient_at_example.com_alias@shroud.test because the alias belongs to someone else"

      assert_no_email_sent()
    end

    test "ignores replies from other users (not the aliases' owner)" do
      other_user = user_fixture()

      args = %{
        from: other_user.email,
        to: ["recipient_at_example.com_alias@shroud.test"],
        data:
          text_email(
            other_user.email,
            ["recipient_at_example.com_alias@shroud.test"],
            "To one recipient",
            "Plain text content"
          )
      }

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Discarding outgoing email from #{other_user.email} to recipient_at_example.com_alias@shroud.test"

      assert_no_email_sent()
    end

    test "does not include reply-to in replies", %{user: user} do
      args = %{
        from: user.email,
        to: ["recipient_at_example.com_alias@shroud.test"],
        data:
          text_email(
            user.email,
            ["recipient_at_example.com_alias@shroud.test"],
            "To one recipient",
            "Plain text content",
            "Reply-To: #{user.email}"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{"recipient@example.com", "recipient@example.com"}]
        assert email.from == {"alias@shroud.test (via Shroud.email)", "alias@shroud.test"}
        assert is_nil(email.reply_to)
      end)
    end

    test "handles existing user emailing other user's alias", %{user: user} do
      other_user = user_fixture()
      other_alias = alias_fixture(%{address: "other@shroud.test", user_id: other_user.id})

      args = %{
        from: user.email,
        to: [other_alias.address],
        data:
          text_email(
            user.email,
            [other_alias.address],
            "To one recipient",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{other_alias.address, other_user.email}]

        assert email.from ==
                 {"#{user.email} (via Shroud.email)", "user_at_example.com_other@shroud.test"}

        assert is_nil(email.reply_to)
      end)
    end

    test "handles text/plain email", %{user: user, email_alias: email_alias} do
      data =
        text_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}

        assert email.from ==
                 {"Sender (via Shroud.email)", "sender_at_example.com_alias@shroud.test"}

        assert is_nil(email.reply_to)
        assert email.text_body =~ "Plain text content!"
        assert is_nil(email.html_body)
      end)
    end

    test "handles text/html email", %{user: user, email_alias: email_alias} do
      data = html_email("sender@example.com", [email_alias.address], "HTML only", @html_content)
      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {email_alias.address, user.email}

        assert email.from ==
                 {"sender@example.com (via Shroud.email)",
                  "sender_at_example.com_alias@shroud.test"}

        assert is_nil(email.reply_to)
        assert is_nil(email.text_body)
        assert email.html_body =~ "This is HTML content"
      end)
    end

    test "handles multipart/alternative email", %{user: user, email_alias: email_alias} do
      data =
        multipart_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Multipart email",
          "Plaintext content",
          @html_content
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}

        assert email.from ==
                 {"Sender (via Shroud.email)", "sender_at_example.com_alias@shroud.test"}

        assert is_nil(email.reply_to)
        assert email.text_body =~ "Plaintext content"
        assert email.html_body =~ "This is HTML content"
      end)
    end

    test "handles unicode email headers (encoded-word)", %{email_alias: email_alias} do
      data =
        text_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Hello, =?utf-8?Q?foo?=",
          "Text body"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.subject == "Hello, foo"
      end)
    end

    test "handles unicode email bodies (quoted-printable)", %{email_alias: email_alias} do
      data =
        text_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Subject",
          "p=C3=A9dagogues",
          "Content-Transfer-Encoding: quoted-printable"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.text_body =~ "pédagogues"
      end)
    end

    test "increments email metrics", %{email_alias: email_alias} do
      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      metric = Repo.get_by!(Aliases.EmailMetric, alias_id: email_alias.id)
      assert metric.forwarded == 1
    end

    test "forwards to non-active account" do
      yesterday =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1 * 60 * 60 * 24)
        |> NaiveDateTime.truncate(:second)

      user = user_fixture(%{status: :trial, trial_expires_at: yesterday})
      email_alias = alias_fixture(%{user_id: user.id})

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.text_body =~ "Plain text content!"
      end)
    end

    test "forwards bounces from outgoing emails" do
      user = user_fixture(%{status: :trial})
      _email_alias = alias_fixture(%{user_id: user.id, address: "alias@shroud.local"})

      data = File.read!("test/support/data/bounce.email") |> Util.lf_to_crlf()

      perform_job(EmailHandler, %{
        from: "MAILER-DAEMON@amazonses.com",
        to: "alias@shroud.local",
        data: data
      })

      assert_email_sent(fn email ->
        assert email.to == [{"alias@shroud.local", user.email}]

        assert email.from ==
                 {"MAILER-DAEMON@amazonses.com (via Shroud.email)",
                  "MAILER-DAEMON_at_amazonses.com_alias@shroud.test"}

        assert email.subject == "Delivery Status Notification (Failure)"

        assert email.text_body =~
                 "The following message to <wrongster@foo.com> was undeliverable."

        assert is_nil(email.html_body)
      end)
    end

    test "does not forward email from a blocked address" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, blocked_addresses: ["sender@example.com"]})

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      assert_no_email_sent()
    end

    test "does not forward when alias is disabled" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, enabled: false})

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      assert_no_email_sent()
      assert Repo.reload!(email_alias).blocked == 1
    end

    test "does not log by default" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) == ""
    end

    test "logs forwarded emails if logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})
      FunWithFlags.enable(:logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Forwarding incoming email from sender@example.com to #{user.email} (via #{email_alias.address})"
    end

    test "logs full email data if verbose logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})
      FunWithFlags.enable(:email_data_logging, for_actor: user)

      Shroud.MockDateTime
      |> stub(:utc_now_unix, fn ->
        1_656_361_719
      end)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      perform_job(EmailHandler, %{from: "sender@example.com", to: email_alias.address, data: data})

      expected_content =
        "To: #{email_alias.address}\r\nFrom: sender@example.com\r\nSubject: Text only\r\nContent-Type: text/plain\r\n\r\nPlain text content!"

      assert_enqueued(
        worker: Shroud.S3.S3UploadJob,
        args: %{
          path: "/emails/sender@example.com-#{email_alias.address}-1656361719.eml",
          content: expected_content
        }
      )
    end

    test "logs blocked emails if logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, blocked_addresses: ["sender@example.com"]})
      FunWithFlags.enable(:logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Blocking incoming email to #{user.email} because the sender (sender@example.com) is blocked"
    end

    test "logs email to disabled aliases if logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, enabled: false})
      FunWithFlags.enable(:logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Discarding incoming email from sender@example.com to disabled alias #{email_alias.address}"
    end
  end

  test "handles 554 rejection notices" do
    raw_email = File.read!("test/support/data/554_rejection_notice.email") |> Util.lf_to_crlf()
    perform_job(EmailHandler, %{from: nil, to: "test@test.com", data: raw_email})

    assert_enqueued(worker: Shroud.S3.S3UploadJob)
  end
end
