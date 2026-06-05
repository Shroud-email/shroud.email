defmodule Shroud.Email.IncomingEmailHandler do
  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Aliases
  alias Shroud.Domain
  alias Shroud.Email
  alias Shroud.Mailer
  alias Shroud.Repo
  alias Shroud.Util

  alias Shroud.Email.{
    SpamHandler,
    ParsedEmail,
    TrackerRemover,
    Enricher,
    ReplyAddress
  }

  import Shroud.Accounts.Logging, only: [maybe_log: 2, store_email: 3]
  require Logger

  @spec handle_incoming_email(String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def handle_incoming_email(sender, recipient, data) do
    # Lookup real email based on the receiving alias (`recipient`)
    recipient_user = Accounts.get_user_by_alias(recipient)
    email_alias = Aliases.get_email_alias_by_address(recipient)
    {_local, recipient_domain} = Util.extract_email_parts(recipient)
    custom_domain = Domain.get_custom_domain(recipient_domain)

    cond do
      email_alias == nil and not is_nil(custom_domain) and custom_domain.catchall_enabled ->
        create_catchall_address(custom_domain, recipient, sender, data)

      recipient_user == nil || email_alias == nil ->
        Logger.notice(
          "Discarding incoming email to unknown address #{recipient} (from #{sender})"
        )

      not email_alias.enabled ->
        maybe_log(
          recipient_user,
          "Discarding incoming email from #{sender} to disabled alias #{recipient}"
        )

        Aliases.increment_blocked!(email_alias)

      Enum.member?(email_alias.blocked_addresses, String.downcase(sender)) ->
        maybe_log(
          recipient_user,
          "Blocking incoming email to #{recipient_user.email} because the sender (#{sender}) is blocked"
        )

        Aliases.increment_blocked!(email_alias)

      SpamHandler.spam?(data) ->
        maybe_log(
          recipient_user,
          "Storing spam email from #{sender} to #{recipient_user.email} (via #{recipient})"
        )

        decoded_email = Mailex.parse!(data)

        SpamHandler.handle_incoming_spam_email(
          sender,
          recipient_user,
          email_alias,
          decoded_email
        )

        Aliases.increment_blocked!(email_alias)

      true ->
        maybe_log(
          recipient_user,
          "Forwarding incoming email from #{sender} to #{recipient_user.email} (via #{recipient})"
        )

        forward_incoming_email(recipient_user, sender, recipient, data)
    end

    :ok
  end

  @spec create_catchall_address(
          Domain.CustomDomain.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: :ok | {:error, term()}
  defp create_catchall_address(
         %Domain.CustomDomain{} = custom_domain,
         recipient,
         sender,
         data
       ) do
    recipient_user = custom_domain.user

    case Aliases.create_email_alias(%{
           user_id: recipient_user.id,
           address: recipient,
           notes: "Created by catch-all"
         }) do
      {:ok, _email_alias} ->
        maybe_log(
          recipient_user,
          "Created alias #{recipient} via catch-all. Forwarding incoming email from #{sender} to #{recipient_user.email}"
        )

        forward_incoming_email(recipient_user, sender, recipient, data)

      {:error, %Ecto.Changeset{} = changeset} ->
        if uniqueness_constraint_error?(changeset, :address) do
          maybe_log(
            recipient_user,
            "Alias #{recipient} already exists (likely created by concurrent catch-all). Forwarding email from #{sender} to #{recipient_user.email}"
          )

          forward_incoming_email(recipient_user, sender, recipient, data)
        else
          maybe_log(
            recipient_user,
            "Could not create catch-all alias #{recipient} (from #{sender}) as the address is invalid. Notifying #{recipient_user.email}."
          )

          notify_catchall_alias_creation_failed(recipient_user, recipient)
        end

      {:error, reason} ->
        maybe_log(
          recipient_user,
          "Could not create catch-all alias #{recipient} (from #{sender}): #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec notify_catchall_alias_creation_failed(User.t(), String.t()) :: :ok
  defp notify_catchall_alias_creation_failed(%User{} = user, recipient) do
    %{
      email_function: :deliver_catchall_alias_creation_failed,
      email_args: [user.id, recipient]
    }
    |> UserNotifierJob.new()
    |> Oban.insert!()

    :ok
  end

  @spec forward_incoming_email(User.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  # Forwards an email (sent to an alias) to the user
  defp forward_incoming_email(%User{} = user, sender, recipient, data) do
    if Accounts.Logging.email_logging_enabled?(user) do
      store_email(sender, recipient, data)
    end

    parsed_email = ParsedEmail.parse(Mailex.parse!(data), sender, recipient)

    processed =
      parsed_email
      |> TrackerRemover.process()
      |> Enricher.process()

    deliver_result =
      processed
      # Now our pipeline is done, we just want our Swoosh email
      |> Map.get(:swoosh_email)
      |> fix_incoming_sender_and_recipient(user.email, sender, recipient)
      |> Mailer.deliver()

    case deliver_result do
      {:ok, _id} ->
        email_alias = Aliases.get_email_alias_by_address!(recipient)

        # Record blocked tracking domains only once the email has actually been
        # forwarded, so that retrying a failed Oban job can't inflate the counts.
        # Both counters live in one transaction so they can't diverge from each
        # other if one write fails.
        Repo.transaction(fn ->
          Aliases.increment_forwarded!(email_alias)
          Email.record_blocked_domains(ParsedEmail.blocked_domains(processed))
        end)

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

  @spec fix_incoming_sender_and_recipient(Swoosh.Email.t(), String.t(), String.t(), String.t()) ::
          Swoosh.Email.t()
  defp fix_incoming_sender_and_recipient(email, recipient_address, sender, email_alias) do
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
        {"", sender}
      else
        # { sender_name, sender_address }
        email.from
      end

    sender_name =
      if sender_name == "" do
        sender_address
      else
        sender_name
      end

    # Remove parentheses and double quotes from sender name to avoid RFC 5322 encoding issues.
    # Parentheses in email display names can cause gen_smtp's mimemail encoder to fail
    # with {:error, {1, :smtp_rfc5322_scan, {:illegal, ~c"("}}} when combined with
    # our " (via Shroud.email)" suffix.
    # Double quotes inside display names cause FunctionClauseError in smtp_util.parse_rfc5322_addresses/1
    # when mimemail tries to re-encode the headers for SMTP delivery.
    # Single quotes (apostrophes) are safe - they're not special characters in RFC 5322.
    sanitized_sender_name =
      sender_name
      |> String.replace(~r/[()"]/, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    reply_address = ReplyAddress.to_reply_address(sender_address, email_alias)
    sender = {sanitized_sender_name <> " (via Shroud.email)", reply_address}

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

  @spec uniqueness_constraint_error?(Ecto.Changeset.t(), atom()) :: boolean()
  defp uniqueness_constraint_error?(changeset, field) do
    Enum.any?(changeset.errors, fn
      {^field, {_message, [constraint: :unique, constraint_name: _name]}} -> true
      _ -> false
    end)
  end
end
