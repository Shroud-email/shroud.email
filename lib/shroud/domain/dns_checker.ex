defmodule Shroud.Domain.DnsChecker do
  use Oban.Worker,
    queue: :dns_checker,
    unique: [
      states: [:available, :scheduled, :executing, :retryable],
      fields: [:worker, :args]
    ]

  alias Phoenix.PubSub
  alias Shroud.Repo
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Domain
  alias Shroud.Domain.CustomDomain
  alias Shroud.Domain.DnsRecord

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"custom_domain_id" => id}}) do
    custom_domain = Repo.get!(CustomDomain, id)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    was_verified_before = Domain.fully_verified?(custom_domain)

    # Ownership
    desired_ownership_records = DnsRecord.desired_ownership_records(custom_domain)
    ownership_verified_at = if has_records?(desired_ownership_records), do: now, else: nil

    # MX
    desired_mx = DnsRecord.desired_mx_records(custom_domain)
    mx_verified_at = if has_records?(desired_mx), do: now, else: nil

    # SPF
    desired_spf = DnsRecord.desired_spf_records(custom_domain)
    spf_verified_at = if has_records?(desired_spf), do: now, else: nil

    # DKIM
    desired_dkim = DnsRecord.desired_dkim_records(custom_domain)
    dkim_verified_at = if has_records?(desired_dkim), do: now, else: nil

    # DMARC
    desired_dmarc = DnsRecord.desired_dmarc_records(custom_domain)
    dmarc_verified_at = if has_records?(desired_dmarc), do: now, else: nil

    # Save
    custom_domain =
      custom_domain
      |> Ecto.Changeset.change(%{
        ownership_verified_at: ownership_verified_at,
        mx_verified_at: mx_verified_at,
        spf_verified_at: spf_verified_at,
        dkim_verified_at: dkim_verified_at,
        dmarc_verified_at: dmarc_verified_at
      })
      |> Repo.update!()

    PubSub.broadcast!(Shroud.PubSub, "dns_checker", :dns_check_complete)

    # Notify the user if we just verified the domain
    if !was_verified_before and Domain.fully_verified?(custom_domain) do
      %{email_function: "deliver_domain_verified", email_args: [custom_domain.id]}
      |> UserNotifierJob.new()
      |> Oban.insert!()
    end

    :ok
  end

  defp has_records?(desired_records) when is_list(desired_records) do
    Enum.all?(desired_records, fn desired_record ->
      actual_records = dns_impl().lookup(desired_record.domain, desired_record.type)
      Enum.any?(actual_records, &is_desired_record?(&1, desired_record.value))
    end)
  end

  defp is_desired_record?({_priority, record}, desired_record),
    do: is_desired_record?(record, desired_record)

  defp is_desired_record?(record, desired_record) do
    record = to_string(record)
    String.downcase(record) == String.downcase(desired_record)
  end

  defp dns_impl() do
    Application.get_env(:shroud, :dns_client, Shroud.DnsClient)
  end
end
