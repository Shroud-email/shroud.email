defmodule Shroud.Email.SpamHandler do
  @moduledoc """
  Handles spam emails (i.e. emails that SpamAssassin consider spam).
  """

  @type email :: :mimemail.mimetuple()

  require Logger
  alias Shroud.Accounts
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Email.ReplyAddress

  @doc """
  Returns true if the the given email has a SpamAssassin score
  greater than SpamAssassin's threshold.

  In other words, configuration of spam detection thresholds etc.
  is done in SpamAssassin, not here.
  """
  @spec is_spam?(email) :: boolean()
  def is_spam?(email) do
    email
    |> get_spamassassin_header()
    |> String.downcase()
    |> String.trim_leading()
    |> String.starts_with?("yes, ")
  end

  # TODO
  # def handle_incoming_spam_email(email) do
  # end

  @spec handle_outgoing_spam_email(email) :: :ok
  def handle_outgoing_spam_email({_mime_type, _mime_subtype, headers, _opts, _body}) do
    sender = get_header_value(headers, "from")
    recipient = get_header_value(headers, "to")

    case Accounts.get_user_by_email(sender) do
      nil ->
        # if we got here, the alias must have been deleted? do nothing.
        :ok

      user ->
        {recipient, email_alias} = ReplyAddress.from_reply_address(recipient)

        %{
          email_function: :deliver_outgoing_email_marked_as_spam,
          email_args: [user.id, email_alias, recipient]
        }
        |> UserNotifierJob.new()
        |> Oban.insert!()

        :ok
    end
  end

  @spec get_spamassassin_header(:mimemail.mimetuple()) :: String.t()
  defp get_spamassassin_header({_mime_type, _mime_subtype, headers, _opts, _body}) do
    case get_header_value(headers, "x-spam-status") do
      "" ->
        sender = get_header_value(headers, "from")
        recipient = get_header_value(headers, "to")

        Logger.warn(
          "Received an email from #{sender} to #{recipient} without a SpamAssassin header"
        )

        ""

      value ->
        value
    end
  end

  defp get_header_value(headers, header_name) do
    case Enum.find(headers, fn {header, _value} ->
           String.downcase(header) == String.downcase(header_name)
         end) do
      {_header_name, value} -> value
      _other -> ""
    end
  end
end
