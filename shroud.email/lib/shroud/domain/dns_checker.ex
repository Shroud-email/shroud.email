defmodule Shroud.Domain.DnsChecker do
  use Oban.Worker,
    queue: :dns_checker,
    unique: [
      states: :incomplete,
      fields: [:worker, :args]
    ]

  alias Phoenix.PubSub
  alias Shroud.Repo
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Domain
  alias Shroud.Domain.CustomDomain
  alias Shroud.Domain.DnsRecord

  @dmarc_values %{
    "p" => ~w(none quarantine reject),
    "sp" => ~w(none quarantine reject),
    "np" => ~w(none quarantine reject),
    "adkim" => ~w(r s),
    "aspf" => ~w(r s),
    "t" => ~w(y n),
    "psd" => ~w(y n u)
  }

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
    dmarc_verified_at = if valid_dmarc_record?(custom_domain), do: now, else: nil

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
    deliver_notification_emails(was_verified_before, custom_domain)
    :ok
  end

  defp deliver_notification_emails(was_verified_before, %CustomDomain{} = custom_domain) do
    # Notify the user if we just verified the domain
    if !was_verified_before and Domain.fully_verified?(custom_domain) do
      %{email_function: "deliver_domain_verified", email_args: [custom_domain.id]}
      |> UserNotifierJob.new()
      |> Oban.insert!()
    end

    # Notify the user if the domain is no longer verified
    if was_verified_before and !Domain.fully_verified?(custom_domain) do
      %{email_function: "deliver_domain_no_longer_verified", email_args: [custom_domain.id]}
      |> UserNotifierJob.new()
      |> Oban.insert!()
    end
  end

  defp has_records?(desired_records) when is_list(desired_records) do
    Enum.all?(desired_records, fn desired_record ->
      actual_records = dns_impl().lookup(desired_record.domain, desired_record.type)
      Enum.any?(actual_records, &desired_record?(&1, desired_record.value))
    end)
  end

  defp desired_record?({_priority, record}, desired_record),
    do: desired_record?(record, desired_record)

  defp desired_record?(record, desired_record) do
    record = to_string(record)
    String.downcase(record) == String.downcase(desired_record)
  end

  defp valid_dmarc_record?(%CustomDomain{domain: domain}) do
    records =
      dns_impl().lookup("_dmarc.#{domain}", :txt)
      |> Enum.map(&IO.iodata_to_binary/1)
      |> Enum.filter(&Regex.match?(~r/^[vV][ \t]*=[ \t]*DMARC1(?:[ \t]*;|[ \t]*$)/, &1))

    case records do
      [record] ->
        [_version | tags] =
          record |> String.split(";") |> Enum.map(&trim_dmarc_whitespace/1)

        tags = if List.last(tags) == "", do: Enum.drop(tags, -1), else: tags
        valid_dmarc_tags?(tags)

      _ ->
        false
    end
  end

  defp valid_dmarc_tags?(tags) do
    pairs =
      Enum.map(tags, fn tag ->
        case Regex.run(~r/\A([a-z]+)[ \t]*=[ \t]*([\t\x20-\x3A\x3C-\x7E]+)\z/i, tag) do
          [_, name, value] -> {String.downcase(name), value}
          nil -> nil
        end
      end)

    names =
      for {name, _value} <- pairs,
          is_map_key(@dmarc_values, name) or name in ~w(v fo rua ruf),
          do: name

    Enum.all?(pairs, &valid_dmarc_tag?/1) and
      names == Enum.uniq(names) and
      "v" not in names and
      ("p" in names or "rua" in names)
  end

  defp valid_dmarc_tag?(nil), do: false

  defp valid_dmarc_tag?({tag, value}) when is_map_key(@dmarc_values, tag),
    do: String.downcase(value) in Map.fetch!(@dmarc_values, tag)

  defp valid_dmarc_tag?({"fo", value}) do
    options = String.downcase(value) |> String.split(":")

    Enum.all?(options, &(&1 in ["0", "1", "d", "s"])) and
      length(Enum.uniq(options)) == length(options) and
      not ("0" in options and "1" in options)
  end

  defp valid_dmarc_tag?({tag, value}) when tag in ["rua", "ruf"] do
    value
    |> String.split(",")
    |> Enum.all?(&valid_dmarc_uri?/1)
  end

  defp valid_dmarc_tag?({_unknown, _value}), do: true

  defp valid_dmarc_uri?(value) do
    value = trim_dmarc_whitespace(value)

    with [uri] <-
           Regex.run(~r/\A([^! \t]+)(?:![0-9]+[kmgt]?)?\z/i, value, capture: :all_but_first),
         false <- Regex.match?(~r/%(?![0-9a-f]{2})/i, uri),
         {:ok, %URI{scheme: scheme} = parsed} when is_binary(scheme) <- URI.new(uri) do
      parsed.host not in [nil, ""] or parsed.path not in [nil, ""]
    else
      _ -> false
    end
  end

  defp trim_dmarc_whitespace(value), do: Regex.replace(~r/\A[ \t]+|[ \t]+\z/, value, "")

  defp dns_impl() do
    Application.get_env(:shroud, :dns_client, Shroud.DnsClient)
  end
end
