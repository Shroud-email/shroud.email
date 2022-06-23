defmodule Shroud.Accounts.EmailOctopusJob do
  use Oban.Worker, queue: :default, max_attempts: 10
  alias Shroud.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    user = Accounts.get_user!(user_id)

    with {:ok, api_key} <- Application.fetch_env(:shroud, :email_octopus_api_key),
         {:ok, list_id} <- Application.fetch_env(:shroud, :email_octopus_list_id) do
      subscribe(user, api_key, list_id)
    else
      :error ->
        # Not configured; do nothing
        :ok
    end
  end

  defp subscribe(user, api_key, list_id) do
    url = "https://emailoctopus.com/api/1.6/lists/#{list_id}/contacts"

    payload =
      Jason.encode!(%{
        api_key: api_key,
        email_address: user.email,
        status: "SUBSCRIBED"
      })

    http().post(url, payload, "Content-Type": "application/json")
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
