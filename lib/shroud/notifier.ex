defmodule Shroud.Notifier do
  @moduledoc """
  Notifies an external service (via webhooks) when certain actions occur.
  """

  alias Shroud.NotifierJob

  def notify_user_started_trial(email) do
    payload = %{
      content: "🧑 **#{email}** just signed up for a free trial!"
    }

    enqueue_webhook(payload)
  end

  def notify_user_signed_up(email) do
    payload = %{
      content: "🎉 **#{email}** just signed up for a paid plan!"
    }

    enqueue_webhook(payload)
  end

  def notify_outgoing_email_marked_as_spam(from, to) do
    payload = %{
      content: "⚠️ Email from **#{from}** to **#{to}** marked as spam by OhMySMTP"
    }

    enqueue_webhook(payload)
  end

  def notify_outgoing_email_bounced(from, to) do
    payload = %{
      content: "⚠️ Email from **#{from}** to **#{to}** hard bounced. Failed to forward!"
    }

    enqueue_webhook(payload)
  end

  defp enqueue_webhook(payload) do
    case Application.fetch_env(:shroud, :notifier_webhook_url) do
      {:ok, nil} ->
        # Not configured; do nothing
        :ok

      {:ok, _url} ->
        %{payload: payload}
        |> NotifierJob.new()
        |> Oban.insert!()
    end
  end
end
