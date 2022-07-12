defmodule Shroud.Email.EmailHandler do
  use Oban.Worker, queue: :outgoing_email, max_attempts: 100
  use Appsignal.Instrumentation.Decorators

  require Logger
  alias Shroud.{Accounts, Aliases, Mailer, Util}
  alias Shroud.Accounts.User

  alias Shroud.Email.{
    BounceHandler,
    Enricher,
    ParsedEmail,
    ReplyAddress,
    TrackerRemover,
    SpamHandler
  }

  alias Shroud.S3.S3UploadJob

  @type mimemail_email :: :mimemail.mimetuple()

  @impl Oban.Worker
  @decorate transaction(:background_job)
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}})
      when from in ["", nil] do
    BounceHandler.handle_haraka_bounce_report(to, data)
  end

  @impl Oban.Worker
  @decorate transaction(:background_job)
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}})
      when byte_size(data) > 26_214_400 do
    # when the email is too big, cancel

    if is_list(to) do
      Enum.each(to, fn recipient ->
        user = Accounts.get_user_by_alias(recipient)
        maybe_log(user, "Dropping email from #{from} to #{recipient} because it's above 25MB")
      end)
    else
      user = Accounts.get_user_by_alias(to)
      maybe_log(user, "Dropping email from #{from} to #{to} because it's above 25MB")
    end

    # silently drop the email. can probably handle this better but not worth it for now.
    :ok
  end

  @impl Oban.Worker
  @decorate transaction(:background_job)
  def perform(%Oban.Job{args: %{"from" => from, "to" => recipients, "data" => data}})
      when is_list(recipients) do
    # TODO: handle parsing failures from mimemail?
    email = :mimemail.decode(data)

    recipients
    |> Enum.each(&handle_recipient(from, &1, email))
  end

  @impl Oban.Worker
  @decorate transaction(:background_job)
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}}) do
    email = :mimemail.decode(data)
    handle_recipient(from, to, email)
  end

  @spec handle_recipient(String.t(), String.t(), mimemail_email) :: :ok | {:error, term()}
  defp handle_recipient(sender, recipient, mimemail_email) do
    if ReplyAddress.is_reply_address?(recipient) do
      handle_outgoing_email(sender, recipient, mimemail_email)
    else
      handle_incoming_email(sender, recipient, mimemail_email)
    end
  end

  @spec handle_incoming_email(String.t(), String.t(), mimemail_email) :: :ok | {:error, term()}
  defp handle_incoming_email(sender, recipient, mimemail_email) do
    # Lookup real email based on the receiving alias (`recipient`)
    recipient_user = Accounts.get_user_by_alias(recipient)
    email_alias = Aliases.get_email_alias_by_address(recipient)

    cond do
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

  @spec handle_outgoing_email(String.t(), String.t(), mimemail_email) :: :ok | {:error, term()}
  defp handle_outgoing_email(sender, recipient, mimemail_email) do
    sender_user = Accounts.get_user_by_email(sender)

    cond do
      SpamHandler.is_spam?(mimemail_email) ->
        SpamHandler.handle_outgoing_spam_email(mimemail_email)

      sender_owns_alias?(sender_user, recipient) ->
        maybe_log(
          sender_user,
          "Forwarding outgoing email from #{sender} to external address #{recipient}"
        )

        forward_outgoing_email(sender_user, sender, recipient, mimemail_email)

      true ->
        Logger.notice(
          "Discarding outgoing email from #{sender} to #{recipient} because the alias belongs to someone else"
        )
    end

    :ok
  end

  @spec forward_outgoing_email(User.t(), String.t(), String.t(), mimemail_email) ::
          :ok | {:error, term()}
  # Forwards a reply (sent to a reply address from a user) to the external address
  defp forward_outgoing_email(%User{} = sender_user, sender, recipient, mimemail_email) do
    if Accounts.Logging.email_logging_enabled?(sender_user) do
      # TODO: test this
      data = :mimemail.encode(mimemail_email)
      store_email(sender, recipient, data)
    end

    case ParsedEmail.parse(mimemail_email)
         |> Map.get(:swoosh_email)
         |> fix_outgoing_sender_and_recipient(recipient)
         |> Mailer.deliver() do
      {:ok, _id} ->
        {_recipient_address, email_alias} = ReplyAddress.from_reply_address(recipient)
        email_alias = Aliases.get_email_alias_by_address!(email_alias)
        Appsignal.increment_counter("emails.replied", 1)
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

  @spec forward_incoming_email(User.t(), String.t(), String.t(), mimemail_email) ::
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

  defp maybe_log(nil, _text), do: :ok

  defp maybe_log(%User{} = user, text) do
    if Accounts.Logging.logging_enabled?(user) do
      Logger.notice(text)
    end
  end

  defp store_email(sender, recipient, data) do
    date_time = Application.get_env(:shroud, :datetime_module, Shroud.DateTime)
    s3_path = "/emails/#{sender}-#{recipient}-#{date_time.utc_now_unix()}.eml"

    %{path: s3_path, content: data}
    |> S3UploadJob.new()
    |> Oban.insert!()

    Logger.notice("Storing email from #{sender} to #{recipient} to #{s3_path}")
  end
end
