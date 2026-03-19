defmodule Shroud.Scheduler do
  use Quantum, otp_app: :shroud

  alias Shroud.Repo
  alias Shroud.Email
  alias Shroud.Domain
  alias Shroud.Domain.{CustomDomain, DnsChecker}

  def update_trackers() do
    %{}
    |> Email.TrackerListFetcher.new()
    |> Oban.insert()
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
