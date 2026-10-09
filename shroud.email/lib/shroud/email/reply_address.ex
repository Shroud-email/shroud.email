defmodule Shroud.Email.ReplyAddress do
  @moduledoc """
  This module translates a sender email address into a "reply address"
  that can receive replies, and vice versa.

  The reply address also contains information about the alias it came from, so
  that we know who to put as the sender when a user sends an outgoing email.
  """

  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Domain
  alias Shroud.Repo
  alias Shroud.Util

  import Ecto.Query

  @dot_atom ~r/\A[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+)*\z/
  @hostname ~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/

  def subdomains_enabled? do
    Application.get_env(:shroud, :reply_address_subdomains_enabled, false)
  end

  defp reply_root, do: "reply." <> String.downcase(Util.email_domain())

  @doc "Returns true for the reserved reply namespace, including malformed routes."
  def reply_domain?(domain) do
    domain = String.downcase(domain)
    domain == reply_root() or String.ends_with?(domain, "." <> reply_root())
  end

  @spec to_reply_address(String.t(), String.t()) :: String.t() | :error
  @doc """
  Convert an email address and an alias to a reply address that the user
  can send replies via. Subdomain generation uses a persisted alias and returns
  `:error` for unsupported or oversized mailboxes. With generation disabled,
  the local-part routing format is used.

  ## Examples:

      iex> Shroud.Email.ReplyAddress.to_reply_address("test@test.com", "deadbeef@email.shroud.test")
      "test_at_test.com_deadbeef@email.shroud.test"
  """
  def to_reply_address(address, email_alias) do
    if subdomains_enabled?() do
      to_subdomain_address(address, email_alias)
    else
      to_legacy_address(address, email_alias)
    end
  end

  defp to_subdomain_address(address, email_alias) do
    {local, domain} = Util.extract_email_parts(address)
    domain = String.downcase(domain)

    with true <- valid_mailbox?(local, domain),
         %EmailAlias{id: id} <- Aliases.get_email_alias_by_address(email_alias) do
      route_domain = "#{encode_domain(domain)}.#{id}.r1.#{reply_root()}"
      if valid_mailbox?(local, route_domain), do: local <> "@" <> route_domain, else: :error
    else
      _ -> :error
    end
  end

  defp to_legacy_address(address, email_alias) do
    {alias_local_part, alias_domain} = Util.extract_email_parts(email_alias)

    Regex.replace(~r/@(.*)$/, address, "_at_\\1") <>
      "_#{alias_local_part}@" <>
      alias_domain
  end

  @spec from_reply_address(String.t()) :: {String.t(), String.t()} | :error
  @doc """
  Returns {email_address, alias}.

  ## Examples:

      iex> Shroud.Email.ReplyAddress.from_reply_address("test_at_test.com_deadbeef@email.shroud.test")
      {"test@test.com", "deadbeef@email.shroud.test"}
  """
  def from_reply_address(address) do
    {local, domain} = Util.extract_email_parts(address)

    if reply_domain?(domain) do
      from_subdomain_address(local, String.downcase(domain))
    else
      from_legacy_address(address)
    end
  end

  defp from_subdomain_address(local, domain) do
    with true <- valid_mailbox?(local, domain),
         prefix <- String.replace_suffix(domain, "." <> reply_root(), ""),
         ["r1", id | reversed_payload] <- prefix |> String.split(".") |> Enum.reverse(),
         {alias_id, ""} when alias_id > 0 and alias_id <= 9_223_372_036_854_775_807 <-
           Integer.parse(id),
         true <- Integer.to_string(alias_id) == id,
         payload <- reversed_payload |> Enum.reverse() |> Enum.join("."),
         {:ok, external_domain} <-
           payload |> String.replace(".", "") |> Base.decode32(case: :mixed, padding: false),
         true <- encode_domain(external_domain) == payload,
         true <- valid_mailbox?(local, external_domain),
         %EmailAlias{address: alias_address} <-
           Repo.one(from a in EmailAlias, where: a.id == ^alias_id and is_nil(a.deleted_at)) do
      {local <> "@" <> external_domain, alias_address}
    else
      _ -> :error
    end
  end

  defp encode_domain(domain) do
    domain
    |> Base.encode32(case: :lower, padding: false)
    |> String.graphemes()
    |> Enum.chunk_every(63)
    |> Enum.map_join(".", &Enum.join/1)
  end

  defp valid_mailbox?(local, domain) do
    byte_size(local) in 1..64 and byte_size(domain) in 1..253 and
      byte_size(local) + byte_size(domain) + 1 <= 254 and
      Regex.match?(@dot_atom, local) and
      Enum.all?(String.split(domain, "."), fn label ->
        byte_size(label) in 1..63 and Regex.match?(@hostname, label)
      end)
  end

  defp from_legacy_address(address) do
    {local_part, domain} = Util.extract_email_parts(address)

    [alias_local_part | rest] =
      local_part
      |> String.split("_")
      |> Enum.reverse()

    local_part = rest |> Enum.reverse() |> Enum.join("_")

    email_address = Regex.replace(~r/_at_(?!.*_at_.*)/, local_part, "@")
    {email_address, alias_local_part <> "@" <> domain}
  end

  @spec reply_address?(String.t()) :: boolean()
  @doc """
  Returns true if the given email is a reply address.
  """
  def reply_address?(address) do
    {_local, domain} = Util.extract_email_parts(address)

    if reply_domain?(domain), do: true, else: legacy_reply_address?(address, domain)
  end

  defp legacy_reply_address?(address, domain) do
    custom_domain = Domain.get_custom_domain(domain)

    domain_regex =
      if is_nil(custom_domain) do
        Regex.escape(Util.email_domain())
      else
        Regex.escape(domain)
      end

    regex_string = "\\A[^\\s]+_at_[^\\s]+@#{domain_regex}\\z"
    regex = Regex.compile!(regex_string)
    Regex.match?(regex, address)
  end
end
