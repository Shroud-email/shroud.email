defmodule Shroud.Accounts.UserNotifierJobTest do
  use Oban.Testing, repo: Shroud.Repo
  use Shroud.DataCase
  import Shroud.AccountsFixtures
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
  end
end
