defmodule Shroud.Email.EmailHandler do
  use Oban.Worker, queue: :outgoing_email
  use Appsignal.Instrumentation.Decorators

  require Logger
  alias Shroud.{Accounts, Aliases, Mailer}
  alias Shroud.Accounts.User
  alias Shroud.Email.{Enricher, ParsedEmail, TrackerRemover}

  @from_email "noreply@app.shroud.email"
  @from_suffix " (via Shroud)"

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
    case Accounts.get_user_by_alias(recipient) do
      nil ->
        Logger.info("Discarding email to unknown address #{recipient} (from #{sender})")
        Appsignal.increment_counter("emails.discarded", 1)

      user ->
        if Accounts.active?(user) do
          forward_email(user, sender, recipient, data)
        else
          Logger.info("Discarding email to #{user.email} because their account isn't active")
          Appsignal.increment_counter("emails.discarded_expired", 1)
        end
    end
  end

  defp forward_email(%User{} = user, sender, recipient, data) do
    Logger.info("Forwarding email from #{sender} to #{user.email} (via #{recipient})")

    ParsedEmail.parse(data)
    |> TrackerRemover.process()
    |> Enricher.process()
    # Now our pipeline is done, we just want our Swoosh email
    |> Map.get(:swoosh_email)
    |> fix_sender_and_recipient(user.email)
    |> Mailer.deliver()

    try do
      email_alias = Aliases.get_email_alias_by_address!(recipient)
      Appsignal.increment_counter("emails.forwarded", 1)
      Aliases.increment_forwarded!(email_alias)
    rescue
      e ->
        Logger.error("Failed to increment stats for email from #{sender} to #{recipient}: #{e}")
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

    email
    |> Map.put(:from, {sender_name <> @from_suffix, @from_email})
    |> Map.put(:to, [{recipient_name, recipient_address}])
  end
end
