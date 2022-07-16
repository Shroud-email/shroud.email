defmodule Shroud.Accounts.UserNotifierJobTest do
  use Oban.Testing, repo: Shroud.Repo
  use Shroud.DataCase
  import Shroud.AccountsFixtures
  import Shroud.DomainFixtures
  import Swoosh.TestAssertions

  alias Shroud.Accounts.UserNotifierJob

  describe "perform/1" do
    test "sends deliver_trial_expiring_notice" do
      trial_expires_at = NaiveDateTime.utc_now() |> NaiveDateTime.add(2 * 24 * 60 * 60)
      user = user_fixture(%{status: :trial, trial_expires_at: trial_expires_at})

      assert {:ok, _email} =
               perform_job(UserNotifierJob, %{
                 email_function: :deliver_trial_expiring_notice,
                 email_args: [user.id]
               })

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        assert recipient == user.email
      end)
    end

    test "sends deliver_trial_expired_notice" do
      trial_expires_at = NaiveDateTime.utc_now() |> NaiveDateTime.add(-1 * 24 * 60 * 60)
      user = user_fixture(%{status: :trial, trial_expires_at: trial_expires_at})

      assert {:ok, _email} =
               perform_job(UserNotifierJob, %{
                 email_function: :deliver_trial_expired_notice,
                 email_args: [user.id]
               })

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        assert recipient == user.email
      end)
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
  end
end
