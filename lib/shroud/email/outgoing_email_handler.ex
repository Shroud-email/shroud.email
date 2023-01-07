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
    sender_user = Accounts.get_user_by_email(sender)

    cond do
      SpamHandler.is_spam?(data) ->
        mimemail_email = :mimemail.decode(data)
        SpamHandler.handle_outgoing_spam_email(mimemail_email)

      sender_owns_alias?(sender_user, recipient) ->
        maybe_log(
          sender_user,
          "Forwarding outgoing email from #{sender} to external address #{recipient}"
        )

        forward_outgoing_email(sender_user, sender, recipient, data)

      true ->
        Logger.notice(
          "Discarding outgoing email from #{sender} to #{recipient} because the alias belongs to someone else"
        )
    end

    :ok
  end

  @spec forward_outgoing_email(User.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  # Forwards a reply (sent to a reply address from a user) to the external address
  defp forward_outgoing_email(%User{} = sender_user, sender, recipient, data) do
    if Accounts.Logging.email_logging_enabled?(sender_user) do
      store_email(sender, recipient, data)
    end

    mimemail_email = :mimemail.decode(data)

    case ParsedEmail.parse(mimemail_email, sender, recipient)
         |> Map.get(:swoosh_email)
         |> fix_outgoing_sender_and_recipient(recipient)
         |> Mailer.deliver() do
      {:ok, _id} ->
        {_recipient_address, email_alias} = ReplyAddress.from_reply_address(recipient)
        email_alias = Aliases.get_email_alias_by_address!(email_alias)
        Aliases.increment_replied!(email_alias)

        :ok

      {:error, {_code, %{"error" => error}}} ->
        Logger.error("Failed to forward email from #{sender} to #{sender_user.email}: #{error}")
        {:error, error}

      {:error, {_code, error}} ->
        Logger.error("Failed to forward email from #{sender} to #{sender_user.email}: #{error}")
        {:error, error}

      {:error, error} ->
        Logger.error("Failed to forward email from #{sender} to #{sender_user.email}: #{error}")
        {:error, error}
    end
  end

  @spec fix_outgoing_sender_and_recipient(Swoosh.Email.t(), String.t()) :: Swoosh.Email.t()
  defp fix_outgoing_sender_and_recipient(email, recipient) do
    {recipient_address, email_alias} = ReplyAddress.from_reply_address(recipient)

    email
    # Fix the sender (replace the user's real email with the alias)
    |> Map.put(:from, {"#{email_alias} (via Shroud.email)", email_alias})
    # Fix the recipient (replace the reply address with the real recipient)
    |> Map.put(:to, [{recipient_address, recipient_address}])
    # Don't forward the reply-to header in replies as it may contain the user's real email
    |> Map.put(:reply_to, nil)
  end

  defp sender_owns_alias?(nil, _reply_address), do: false

  defp sender_owns_alias?(user, reply_address) do
    {_recipient_address, email_alias} = ReplyAddress.from_reply_address(reply_address)
    email_alias = Aliases.get_email_alias_by_address(email_alias)
    not is_nil(email_alias) && email_alias.user_id == user.id
  end
end
