defmodule Shroud.Accounts.UserNotifierJobTest do
  use Oban.Testing, repo: Shroud.Repo
  use Shroud.DataCase
  import Shroud.AccountsFixtures
  import Shroud.DomainFixtures
  import Swoosh.TestAssertions

  alias Shroud.Accounts.UserNotifierJob

  describe "perform/1" do
    test "sends bounce notifications with escaped HTML and a plain-text fallback" do
      user = user_fixture()

      for subject <- ["<strong>Quote & café</strong>", nil] do
        assert {:ok, email} =
                 perform_job(UserNotifierJob, %{
                   email_function: :deliver_outgoing_email_bounced,
                   email_args: [
                     user.id,
                     "alias@email.shroud.test",
                     "recipient@example.org",
                     subject,
                     "The recipient's address was rejected.",
                     "5.1.1"
                   ]
                 })

        assert_email_sent(to: user.email, subject: "Your email was not delivered")
        document = Floki.parse_document!(email.html_body)
        assert [] == Floki.find(document, "strong")

        for body <- [email.text_body, Floki.text(document)] do
          assert body =~ "recipient@example.org via alias@email.shroud.test"
          assert body =~ "The recipient's address was rejected."
          assert body =~ "Delivery status: 5.1.1"

          if subject do
            assert body =~ "Subject: #{subject}"
          else
            refute body =~ "Subject:"
          end
        end
      end
    end

    test "sends subscription_downgraded with pause-aware wording and a billing link" do
      user = user_fixture(%{status: :free})

      assert {:ok, email} =
               perform_job(UserNotifierJob, %{
                 "email_function" => "deliver_subscription_downgraded",
                 "email_args" => [user.id]
               })

      assert_email_sent(
        to: user.email,
        subject: "Your Shroud.email account is now on the free plan"
      )

      document = Floki.parse_document!(email.html_body)

      for body <- [email.text_body, Floki.text(document)] do
        assert body =~ "Your account is now on the free plan."
        assert body =~ "If your subscription is paused, reply to this email for help resuming it."
        assert body =~ "If it has ended, visit your billing page to sign up again"
        refute body =~ "Your paid Shroud.email subscription has ended"
      end

      assert email.reply_to == {"Shroud.email", "contact@shroud.email"}
      assert email.text_body =~ ShroudWeb.Endpoint.url() <> "/settings/billing"

      assert document
             |> Floki.find("a[href='#{ShroudWeb.Endpoint.url()}/settings/billing']")
             |> Floki.text() == "View billing"
    end

    test "sends domain_verified" do
      user = user_fixture()
      domain = custom_domain_fixture(%{user_id: user.id})

      assert {:ok, _email} =
               perform_job(UserNotifierJob, %{
                 email_function: :deliver_domain_verified,
                 email_args: [domain.id]
               })

      assert_email_sent(to: user.email, subject: "Your domain has been verified")
    end

    test "sends domain_no_longer_verified" do
      user = user_fixture()
      domain = custom_domain_fixture(%{user_id: user.id})

      assert {:ok, _email} =
               perform_job(UserNotifierJob, %{
                 email_function: :deliver_domain_no_longer_verified,
                 email_args: [domain.id]
               })

      assert_email_sent(to: user.email, subject: "#{domain.domain} is no longer verified")
    end

    test "sends confirmation_instructions (dispatched by string name, as enqueued)" do
      user = user_fixture()

      assert {:ok, _email} =
               perform_job(UserNotifierJob, %{
                 "email_function" => "deliver_confirmation_instructions",
                 "email_args" => [user.id, "https://example.com/confirm/token"]
               })

      assert_email_sent(to: user.email, subject: "Confirmation instructions")
    end
  end
end
