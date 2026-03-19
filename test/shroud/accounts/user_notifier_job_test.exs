defmodule Shroud.Accounts.UserNotifierJobTest do
  use Oban.Testing, repo: Shroud.Repo
  use Shroud.DataCase
  import Shroud.AccountsFixtures
  import Shroud.DomainFixtures
  import Swoosh.TestAssertions

  alias Shroud.Accounts.UserNotifierJob

  describe "perform/1" do
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
  end
end
