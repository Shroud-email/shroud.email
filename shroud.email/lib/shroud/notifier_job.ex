defmodule Shroud.NotifierJob do
  use Oban.Worker, queue: :notifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => payload}}) do
    url = Application.fetch_env!(:shroud, :notifier_webhook_url)
    payload = Jason.encode!(payload)
    http().post(url, payload, "Content-Type": "application/json")
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
