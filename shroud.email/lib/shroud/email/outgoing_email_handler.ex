defmodule Shroud.Email.OutgoingEmailHandler do
  require Logger
  alias Shroud.{Accounts, Aliases, Mailer}
  alias Shroud.Accounts.User

  alias Shroud.Email.{
    ParsedEmail,
    ReplyAddress,
    SpamHandler
  }

  import Shroud.Accounts.Logging, only: [maybe_log: 2, store_email: 3]

  @spec handle_outgoing_email(String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def handle_outgoing_email(sender, recipient, data) do
    case ReplyAddress.from_reply_address(recipient) do
      :error -> :ok
      route -> handle_reply(sender, recipient, data, route)
    end
  end

  defp handle_reply(sender, recipient, data, {_external_address, alias_address} = route) do
    sender_user = Accounts.get_user_by_email(sender)
    email_alias = Aliases.get_email_alias_by_address(alias_address)

    cond do
      SpamHandler.spam?(data) ->
        mimemail_email = :mimemail.decode(data)
        SpamHandler.handle_outgoing_spam_email(mimemail_email, route)

      is_nil(sender_user) or not Accounts.paid?(sender_user) ->
        Logger.notice(
          "Discarding outgoing email from #{sender} to #{recipient} because user is not on a paid plan"
        )

      not is_nil(email_alias) and email_alias.user_id == sender_user.id ->
        maybe_log(
          sender_user,
          "Forwarding outgoing email from #{sender} to external address #{recipient}"
        )

        forward_outgoing_email(sender_user, sender, recipient, data, route, email_alias)

      true ->
        Logger.notice(
          "Discarding outgoing email from #{sender} to #{recipient} because the alias belongs to someone else"
        )
    end
    |> case do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  # Forwards a reply (sent to a reply address from a user) to the external address
  defp forward_outgoing_email(%User{} = sender_user, sender, recipient, data, route, email_alias) do
    if Accounts.Logging.email_logging_enabled?(sender_user) do
      store_email(sender, recipient, data)
    end

    mimemail_email = :mimemail.decode(data)

    case ParsedEmail.parse(mimemail_email, sender, recipient)
         |> Map.get(:swoosh_email)
         |> fix_outgoing_sender_and_recipient(route, sender_user)
         |> Mailer.deliver() do
      {:ok, _id} ->
        Shroud.Analytics.outgoing_email_sent()
        Aliases.increment_replied!(email_alias)

        :ok

      {:error, {_code, %{"error" => error}}} ->
        Logger.error(
          "Failed to forward email from #{sender} to #{sender_user.email}: #{inspect(error)}"
        )

        {:error, error}

      {:error, {_code, error}} ->
        Logger.error(
          "Failed to forward email from #{sender} to #{sender_user.email}: #{inspect(error)}"
        )

        {:error, error}

      {:error, error} ->
        Logger.error(
          "Failed to forward email from #{sender} to #{sender_user.email}: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  defp fix_outgoing_sender_and_recipient(email, {recipient_address, email_alias}, user) do
    suffix = if Accounts.email_branding_enabled?(user), do: " (via Shroud.email)", else: ""

    email
    # Fix the sender (replace the user's real email with the alias)
    |> Map.put(:from, {email_alias <> suffix, email_alias})
    # Fix the recipient (replace the reply address with the real recipient)
    |> Map.put(:to, [{recipient_address, recipient_address}])
    # Don't forward the reply-to header in replies as it may contain the user's real email
    |> Map.put(:reply_to, nil)
  end
end
