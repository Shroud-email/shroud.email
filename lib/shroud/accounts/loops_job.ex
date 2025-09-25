defmodule Shroud.Accounts.LoopsJob do
  use Oban.Worker, queue: :default, max_attempts: 10
  alias Shroud.Accounts

  @loops_endpoint "https://app.loops.so/api/v1/contacts/create"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    user = Accounts.get_user!(user_id)

    with {:ok, api_key} <- Application.fetch_env(:shroud, :loops_api_key),
         {:ok, newsletter_id} <- Application.fetch_env(:shroud, :loops_newsletter_id) do
      subscribe(user, api_key, newsletter_id)
    else
      :error ->
        # Not configured; do nothing
        :ok
    end
  end

  defp subscribe(user, api_key, newsletter_id) do
    payload =
      Jason.encode!(%{
        "email" => user.email,
        "newsletterId" => newsletter_id
      })

    headers = [
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    ]

    http().post(@loops_endpoint, payload, headers)
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
