defmodule Shroud.NotifierJob do
  use Oban.Worker, queue: :notifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => payload}}) do
    case Application.get_env(:shroud, :notifier_webhook_url) do
      url when url in [nil, ""] ->
        :ok

      url ->
        payload = Jason.encode!(payload)
        http().post(url, payload, "Content-Type": "application/json")
    end
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
