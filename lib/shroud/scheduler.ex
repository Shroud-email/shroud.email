defmodule Shroud.Scheduler do
  use Quantum, otp_app: :shroud

  alias Shroud.Repo
  alias Shroud.Accounts
  alias Shroud.Email
  alias Shroud.Domain
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Domain.{CustomDomain, DnsChecker}

  def update_trackers() do
    %{}
    |> Email.TrackerListFetcher.new()
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

  def verify_custom_domains() do
    Repo.transaction(fn ->
      CustomDomain
      |> Repo.stream(max_rows: 100)
      |> Stream.each(&schedule_dns_checker_job/1)
      |> Stream.run()
    end)
  end

  def delete_spam_emails() do
    Email.delete_old_spam_emails()
  end

  defp schedule_dns_checker_job(%CustomDomain{} = custom_domain) do
    if Domain.fully_verified?(custom_domain) do
      # delay by up to one hour to evenly distribute jobs
      delay = :rand.uniform(60 * 60)

      %{custom_domain_id: custom_domain.id}
      |> DnsChecker.new(schedule_in: delay)
      |> Oban.insert!()
    else
      # domain isn't verified, so check DNS immediately
      %{custom_domain_id: custom_domain.id}
      |> DnsChecker.new()
      |> Oban.insert!()
    end
  end
end
