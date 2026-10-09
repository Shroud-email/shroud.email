defmodule Shroud.Accounts.UserNotifierJobTest do
  use Oban.Testing, repo: Shroud.Repo
  use Shroud.DataCase
  import Shroud.AccountsFixtures
  import Shroud.DomainFixtures
  import Swoosh.TestAssertions

  alias Shroud.Accounts.UserNotifierJob

  describe "perform/1" do
    test "sends subscription_ended with a billing link in both email bodies" do
      user = user_fixture(%{status: :free})

      assert {:ok, email} =
               perform_job(UserNotifierJob, %{
                 "email_function" => "deliver_subscription_ended",
                 "email_args" => [user.id]
               })

      assert_email_sent(to: user.email, subject: "Your Shroud.email subscription has ended")
      assert email.text_body =~ "Your account is now on the free plan."
      assert email.text_body =~ "sign up again"
      assert email.text_body =~ ShroudWeb.Endpoint.url() <> "/settings/billing"

      document = Floki.parse_document!(email.html_body)
      assert Floki.text(document) =~ "Your account is now on the free plan."

      assert document
             |> Floki.find("a[href='#{ShroudWeb.Endpoint.url()}/settings/billing']")
             |> Floki.text() == "Sign up again"
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
