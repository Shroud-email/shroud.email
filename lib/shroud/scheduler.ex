defmodule Shroud.Scheduler do
  use Quantum, otp_app: :shroud

  alias Shroud.Accounts
  alias Shroud.Email.TrackerListFetcher
  alias Shroud.Accounts.UserNotifierJob

  def update_trackers() do
    %{}
    |> TrackerListFetcher.new()
    |> Oban.insert()
  end

  # Emails users whose trials are expiring between 48-72 hours from now
  def email_expiring_trials() do
    now = NaiveDateTime.utc_now()
    two_days_from_now = NaiveDateTime.add(now, 2 * 24 * 60 * 60)
    three_days_from_now = NaiveDateTime.add(now, 3 * 24 * 60 * 60)

    Accounts.list_users_with_trial_expiry_between(two_days_from_now, three_days_from_now)
    |> Enum.each(fn user ->
      %{email_function: :deliver_trial_expiring_notice, email_args: [user.id]}
      |> UserNotifierJob.new()
      |> Oban.insert()
    end)
  end

  # Emails users whose trials expired in the last 24 hours
  def email_expired_trials() do
    now = NaiveDateTime.utc_now()
    one_day_ago = NaiveDateTime.add(now, -1 * 24 * 60 * 60)

    Accounts.list_users_with_trial_expiry_between(one_day_ago, now)
    |> Enum.each(fn user ->
      %{email_function: :deliver_trial_expired_notice, email_args: [user.id]}
      |> UserNotifierJob.new()
      |> Oban.insert()
    end)
  end
end
