defmodule Shroud.Email.IncomingEmailHandler do
  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias Shroud.Aliases
  alias Shroud.Mailer
  alias Shroud.Util
  alias Shroud.Domain
  alias Shroud.Email.{SpamHandler, ParsedEmail, TrackerRemover, Enricher, ReplyAddress}
  import Shroud.Accounts.Logging, only: [maybe_log: 2, store_email: 3]
  require Logger

  @spec handle_incoming_email(String.t(), String.t(), :mimemail.mimetuple()) ::
          :ok | {:error, term()}
  def handle_incoming_email(sender, recipient, mimemail_email) do
    # Lookup real email based on the receiving alias (`recipient`)
    recipient_user = Accounts.get_user_by_alias(recipient)
    email_alias = Aliases.get_email_alias_by_address(recipient)
    {_local, recipient_domain} = Util.extract_email_parts(recipient)
    custom_domain = Domain.get_custom_domain(recipient_domain)

    cond do
      not is_nil(custom_domain) and custom_domain.catchall_enabled ->
        recipient_user = custom_domain.user

        {:ok, _email_alias} =
          Aliases.create_email_alias(%{
            user_id: recipient_user.id,
            address: recipient,
            notes: "Created by catch-all"
          })

        maybe_log(
          recipient_user,
          "Created alias #{recipient} via catch-all. Forwarding incoming email from #{sender} to #{recipient_user.email}"
        )

        forward_incoming_email(recipient_user, sender, recipient, mimemail_email)

      recipient_user == nil || email_alias == nil ->
        Logger.notice(
          "Discarding incoming email to unknown address #{recipient} (from #{sender})"
        )

        Appsignal.increment_counter("emails.discarded", 1)

      not email_alias.enabled ->
        maybe_log(
          recipient_user,
          "Discarding incoming email from #{sender} to disabled alias #{recipient}"
        )

        Aliases.increment_blocked!(email_alias)
        Appsignal.increment_counter("emails.blocked", 1)

      Enum.member?(email_alias.blocked_addresses, String.downcase(sender)) ->
        maybe_log(
          recipient_user,
          "Blocking incoming email to #{recipient_user.email} because the sender (#{sender}) is blocked"
        )

        Aliases.increment_blocked!(email_alias)
        Appsignal.increment_counter("emails.blocked", 1)

      SpamHandler.is_spam?(mimemail_email) ->
        maybe_log(
          recipient_user,
          "Storing spam email from #{sender} to #{recipient_user.email} (via #{recipient})"
        )

        SpamHandler.handle_incoming_spam_email(
          sender,
          recipient_user,
          email_alias,
          mimemail_email
        )

        Aliases.increment_blocked!(email_alias)
        Appsignal.increment_counter("emails.spam", 1)

      true ->
        maybe_log(
          recipient_user,
          "Forwarding incoming email from #{sender} to #{recipient_user.email} (via #{recipient})"
        )

        forward_incoming_email(recipient_user, sender, recipient, mimemail_email)
    end

    :ok
  end

  @spec forward_incoming_email(User.t(), String.t(), String.t(), :mimemail.mimetuple()) ::
          :ok | {:error, term()}
  # Forwards an email (sent to an alias) to the user
  defp forward_incoming_email(%User{} = user, sender, recipient, mimemail_email) do
    if Accounts.Logging.email_logging_enabled?(user) do
      # TODO: test this
      data = :mimemail.encode(mimemail_email)
      store_email(sender, recipient, data)
    end

    case ParsedEmail.parse(mimemail_email)
         |> TrackerRemover.process()
         |> Enricher.process()
         # Now our pipeline is done, we just want our Swoosh email
         |> Map.get(:swoosh_email)
         |> fix_incoming_sender_and_recipient(user.email, recipient)
         |> Mailer.deliver() do
      {:ok, _id} ->
        email_alias = Aliases.get_email_alias_by_address!(recipient)
        Appsignal.increment_counter("emails.forwarded", 1)
        Aliases.increment_forwarded!(email_alias)

      {:error, {_code, %{"error" => error}}} ->
        Logger.error("Failed to forward email from #{sender} to #{user.email}: #{error}")
        {:error, error}

      {:error, {_code, error}} ->
        Logger.error("Failed to forward email from #{sender} to #{user.email}: #{error}")
        {:error, error}

      {:error, error} ->
        Logger.error("Failed to forward email from #{sender} to #{user.email}: #{error}")
        {:error, error}
    end
  end

  @spec fix_incoming_sender_and_recipient(Swoosh.Email.t(), String.t(), String.t()) ::
          Swoosh.Email.t()
  defp fix_incoming_sender_and_recipient(email, recipient_address, email_alias) do
    # Modify the email to make it clear it came from us
    recipient_name =
      if is_list(email.to) and length(email.to) == 1 do
        [{recipient_name, _alias}] = email.to
        recipient_name
      else
        ""
      end

    {sender_name, sender_address} =
      if is_nil(email.from) do
        {"", "noreply@#{Util.email_domain()}"}
      else
        # { sender_name, sender_address }
        email.from
      end

    reply_address = ReplyAddress.to_reply_address(sender_address, email_alias)
    sender = {sender_name <> " (via Shroud.email)", reply_address}

    email
    |> Map.put(:from, sender)
    |> Map.put(:to, [{recipient_name, recipient_address}])
    |> (fn email ->
          if email.reply_to == nil do
            email
          else
            {_name, reply_to_address} = email.reply_to
            reply_to_reply_address = ReplyAddress.to_reply_address(reply_to_address, email_alias)
            email |> Map.put(:reply_to, {reply_to_reply_address, reply_to_reply_address})
          end
        end).()
  end
end
