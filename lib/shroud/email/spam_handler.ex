defmodule Shroud.Email.SpamHandler do
  @moduledoc """
  Handles spam emails (i.e. emails that SpamAssassin consider spam).
  """

  @type email :: :mimemail.mimetuple()

  require Logger
  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Email
  alias Shroud.Email.ReplyAddress
  alias Shroud.Email.ParsedEmail
  alias Shroud.Email.TrackerRemover

  @doc """
  Returns true if the the given email has a SpamAssassin score
  greater than SpamAssassin's threshold.

  In other words, configuration of spam detection thresholds etc.
  is done in SpamAssassin, not here.
  """
  @spec is_spam?(String.t()) :: boolean()
  def is_spam?(data) do
    email = :mimemail.decode(data)

    email
    |> get_spamassassin_header()
    |> String.downcase()
    |> String.trim_leading()
    |> String.starts_with?("yes, ")
  end

  @spec handle_incoming_spam_email(String.t(), User.t(), EmailAlias.t(), email) :: :ok
  def handle_incoming_spam_email(sender, recipient_user, email_alias, email) do
    parsed_email =
      email
      |> ParsedEmail.parse()
      |> TrackerRemover.process()

    Email.store_spam_email!(
      %{
        from: sender,
        subject: parsed_email.swoosh_email.subject,
        html_body: parsed_email.swoosh_email.html_body,
        text_body: parsed_email.swoosh_email.text_body
      },
      recipient_user,
      email_alias
    )

    %{
      email_function: :deliver_incoming_email_marked_as_spam,
      email_args: [recipient_user.id, email_alias.address]
    }
    |> UserNotifierJob.new()
    |> Oban.insert!()

    :ok
  end

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
