defmodule Shroud.Email.EmailHandler do
  use Oban.Worker, queue: :outgoing_email, max_attempts: 100
  use Appsignal.Instrumentation.Decorators

  require Logger
  alias Shroud.{Accounts, Aliases, Mailer, Util}
  alias Shroud.Accounts.User
  alias Shroud.Email.{Enricher, ParsedEmail, TrackerRemover}

  @impl Oban.Worker
  @decorate transaction(:background_job)
  def perform(%Oban.Job{args: %{"from" => from, "to" => recipients, "data" => data}})
      when is_list(recipients) do
    recipients
    |> Enum.each(&handle_recipient(from, &1, data))
  end

  @impl Oban.Worker
  @decorate transaction(:background_job)
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}}) do
    handle_recipient(from, to, data)
  end

  defp handle_recipient(sender, recipient, data) do
    # Lookup real email based on the receiving alias (`recipient`)
    user = Accounts.get_user_by_alias(recipient)
    email_alias = Aliases.get_email_alias_by_address(recipient)

    cond do
      user == nil || email_alias == nil ->
        Logger.info("Discarding email to unknown address #{recipient} (from #{sender})")
        Appsignal.increment_counter("emails.discarded", 1)

      not email_alias.enabled ->
        maybe_log(user, "Discarding email from #{sender} to disabled alias #{recipient}")
        Aliases.increment_blocked!(email_alias)
        Appsignal.increment_counter("emails.blocked", 1)

      Enum.member?(email_alias.blocked_addresses, String.downcase(sender)) ->
        maybe_log(
          user,
          "Blocking email to #{user.email} because the sender (#{sender}) is blocked"
        )

        Aliases.increment_blocked!(email_alias)
        Appsignal.increment_counter("emails.blocked", 1)

      true ->
        forward_email(user, sender, recipient, data)
    end
  end

  defp forward_email(%User{} = user, sender, recipient, data) do
    maybe_log(user, "Forwarding email from #{sender} to #{user.email} (via #{recipient})")

    if FunWithFlags.enabled?(:email_data_logging, for: user) do
      Logger.info("Email data: #{data}")
    end

    case ParsedEmail.parse(data)
         |> TrackerRemover.process()
         |> Enricher.process()
         # Now our pipeline is done, we just want our Swoosh email
         |> Map.get(:swoosh_email)
         |> fix_sender_and_recipient(user.email)
         |> Mailer.deliver() do
      {:ok, _id} ->
        email_alias = Aliases.get_email_alias_by_address!(recipient)
        Appsignal.increment_counter("emails.forwarded", 1)
        Aliases.increment_forwarded!(email_alias)

      {:error, {_code, %{"error" => error}}} ->
        Logger.error("Failed to forward email from #{sender} to #{user.email}: #{error}")
        {:error, error}

      {:error, error} ->
        Logger.error("Failed to forward email from #{sender} to #{user.email}: #{error}")
        {:error, error}
    end
  end

  @spec fix_sender_and_recipient(Swoosh.Email.t(), String.t()) :: Swoosh.Email.t()
  defp fix_sender_and_recipient(email, recipient_address) do
    # Modify the email to make it clear it came from us
    recipient_name =
      if is_list(email.to) and Enum.empty?(email.to) do
        ""
      else
        [{recipient_name, _alias}] = email.to
        recipient_name
      end

    sender_name =
      if is_nil(email.reply_to) do
        ""
      else
        {sender_name, _sender_address} = email.reply_to
        sender_name
      end

    sender = {sender_name <> " (via Shroud.email)", "noreply@#{Util.email_domain()}"}

    email
    |> Map.put(:from, sender)
    |> Map.put(:to, [{recipient_name, recipient_address}])
  end

  defp maybe_log(%User{} = user, text) do
    if FunWithFlags.enabled?(:logging, for: user) do
      Logger.info(text)
    end
  end
end
