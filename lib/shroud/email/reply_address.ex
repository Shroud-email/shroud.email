defmodule Shroud.Email.ReplyAddress do
  @moduledoc """
  This module translates sender email address into an @shroud.email address
  that can receive replies, and vice versa.

  The reply address also contains information about the alias it came from, so
  that we know who to put as the sender when a user sends an outgoing email.
  """

  alias Shroud.Util

  @spec to_reply_address(String.t(), String.t()) :: String.t()
  @doc """
  Convert an email address and an alias to a reply address that the user
  can send replies via.

  Example:

  ReplyAddress.to_reply_address("test@test.com", "deadbeef@shroud.test")
  > "test_at_test.com_deadbeef@shroud.test"
  """
  def to_reply_address(address, email_alias) do
    # Get the first part of the alias, i.e. everything before the @
    alias_address_part = Regex.replace(~r/@(.*)$/, email_alias, "")

    Regex.replace(~r/@(.*)$/, address, "_at_\\1") <>
      "_#{alias_address_part}@" <>
      Util.email_domain()
  end

  @spec from_reply_address(String.t()) :: {String.t(), String.t()}
  @doc """
  Returns {email_address, alias}.

  Example:

  ReplyAddress.from_reply_address("test_at_test.com_deadbeef@shroud.test"})
  > {"test@test.com", "deadbeef@shroud.test"}
  """
  def from_reply_address(address) do
    address = String.replace_suffix(address, "@" <> Util.email_domain(), "")

    [alias_address_part | rest] =
      address
      |> String.split("_")
      |> Enum.reverse()

    address = rest |> Enum.reverse() |> Enum.join("_")

    email_address = Regex.replace(~r/_at_(?!.*_at_.*)/, address, "@")
    {email_address, alias_address_part <> "@" <> Util.email_domain()}
  end

  @spec is_reply_address?(String.t()) :: boolean()
  @doc """
  Returns true if the given email is a reply address.
  """
  def is_reply_address?(address) do
    domain_regex = Util.email_domain() |> String.replace(".", "\.")
    regex_string = "[^\s]+_at_[^\s]+@#{domain_regex}"
    regex = Regex.compile!(regex_string)
    Regex.match?(regex, address)
  end
end
