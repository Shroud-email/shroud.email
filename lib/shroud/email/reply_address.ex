defmodule Shroud.Email.ReplyAddress do
  @moduledoc """
  This module translates a sender email address into a "reply address"
  that can receive replies, and vice versa.

  The reply address also contains information about the alias it came from, so
  that we know who to put as the sender when a user sends an outgoing email.
  """

  alias Shroud.Util
  alias Shroud.Domain

  @spec to_reply_address(String.t(), String.t()) :: String.t()
  @doc """
  Convert an email address and an alias to a reply address that the user
  can send replies via.

  ## Examples:

      iex> Shroud.Email.ReplyAddress.to_reply_address("test@test.com", "deadbeef@shroud.test")
      "test_at_test.com_deadbeef@shroud.test"
  """
  def to_reply_address(address, email_alias) do
    {alias_local_part, alias_domain} = Util.extract_email_parts(email_alias)

    Regex.replace(~r/@(.*)$/, address, "_at_\\1") <>
      "_#{alias_local_part}@" <>
      alias_domain
  end

  @spec from_reply_address(String.t()) :: {String.t(), String.t()}
  @doc """
  Returns {email_address, alias}.

  ## Examples:

      iex> Shroud.Email.ReplyAddress.from_reply_address("test_at_test.com_deadbeef@shroud.test")
      {"test@test.com", "deadbeef@shroud.test"}
  """
  def from_reply_address(address) do
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
    # This code currently requires a DB call to check if the domain
    # is a user's custom domain. It'd be nice to eventually refactor
    # reply addresses so they don't require a DB call.
    {_local, domain} = Util.extract_email_parts(address)
    custom_domain = Domain.get_custom_domain(domain)

    domain_regex =
      if is_nil(custom_domain) do
        Util.email_domain() |> String.replace(".", "\.")
      else
        domain |> String.replace(".", "\.")
      end

    regex_string = "[^\s]+_at_[^\s]+@#{domain_regex}"
    regex = Regex.compile!(regex_string)
    Regex.match?(regex, address)
  end
end
