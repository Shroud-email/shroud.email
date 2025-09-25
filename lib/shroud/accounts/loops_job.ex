defmodule Shroud.Accounts.LoopsJob do
  use Oban.Worker, queue: :default, max_attempts: 10
  alias Shroud.Accounts
  require Logger

  @loops_endpoint "https://app.loops.so/api/v1/events/send"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "user_id" => user_id,
          "event_name" => event_name,
          "event_properties" => event_properties,
          "mailing_lists" => mailing_lists
        }
      }) do
    user = Accounts.get_user!(user_id)

    case Application.fetch_env(:shroud, :loops_api_key) do
      {:ok, api_key} ->
        track_event(user, event_name, event_properties, api_key, mailing_lists)

      :error ->
        # Not configured; do nothing
        :ok
    end
  end

  defp track_event(user, event_name, properties, api_key, mailing_lists) do
    payload =
      Jason.encode!(%{
        "email" => user.email,
        "eventName" => event_name,
        "eventProperties" => properties,
        "mailingLists" => mailing_lists
      })

    headers = [
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    ]

    Logger.info("Tracking #{event_name} for user #{user.email} in Loops")
    http().post(@loops_endpoint, payload, headers)
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
