defmodule Shroud.Accounts.LoopsJob do
  use Oban.Worker, queue: :default, max_attempts: 10
  alias Shroud.Accounts
  require Logger

  @events_endpoint "https://app.loops.so/api/v1/events/send"
  @contacts_endpoint "https://app.loops.so/api/v1/contacts/update"
  @contact_properties_endpoint "https://app.loops.so/api/v1/contacts/properties"

  def ensure_contact_properties do
    with {:ok, api_key} <- api_key(),
         {:ok, properties} <- list_contact_properties(api_key) do
      ensure_status_property(properties, api_key)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "sync_loops", "user_id" => user_id}}) do
    user_id
    |> Accounts.get_user!()
    |> sync_contact()
  end

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

    with_api_key(fn api_key ->
      track_event(user, event_name, event_properties, api_key, mailing_lists)
    end)
  end

  defp sync_contact(%{status: :lead}), do: :ok

  defp sync_contact(user) do
    with_api_key(&update_contact(user, &1))
  end

  defp update_contact(user, api_key) do
    payload =
      user
      |> contact_properties()
      |> Map.put("email", user.email)
      |> Jason.encode!()

    Logger.info("Syncing user #{user.email} to Loops")

    http().put(@contacts_endpoint, payload, headers(api_key), [])
    |> handle_response()
  end

  defp track_event(user, event_name, properties, api_key, mailing_lists) do
    payload =
      %{
        "email" => user.email,
        "eventName" => event_name,
        "eventProperties" => properties,
        "mailingLists" => mailing_lists
      }
      |> Map.merge(contact_properties(user))
      |> Jason.encode!()

    Logger.info("Tracking #{event_name} for user #{user.email} in Loops")

    http().post(@events_endpoint, payload, headers(api_key))
    |> handle_response()
  end

  defp contact_properties(user), do: %{"status" => Atom.to_string(user.status)}

  defp with_api_key(fun) do
    case api_key() do
      {:ok, api_key} -> fun.(api_key)
      {:error, :loops_not_configured} -> :ok
    end
  end

  defp api_key do
    case Application.get_env(:shroud, :loops_api_key) do
      api_key when is_binary(api_key) and byte_size(api_key) > 0 -> {:ok, api_key}
      _missing -> {:error, :loops_not_configured}
    end
  end

  defp list_contact_properties(api_key) do
    http().get(@contact_properties_endpoint <> "?list=custom", headers(api_key), [])
    |> decode_contact_properties()
  end

  defp decode_contact_properties({:ok, %HTTPoison.Response{status_code: status, body: body}})
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, properties} when is_list(properties) -> {:ok, properties}
      _invalid_json -> {:error, {:invalid_loops_response, body}}
    end
  end

  defp decode_contact_properties(response), do: handle_response(response)

  defp ensure_status_property(properties, api_key) do
    case Enum.find(properties, &(&1["key"] == "status")) do
      nil -> create_status_property(api_key)
      %{"type" => "string"} -> :ok
      %{"type" => type} -> {:error, {:invalid_contact_property_type, "status", type}}
    end
  end

  defp create_status_property(api_key) do
    payload = Jason.encode!(%{"name" => "status", "type" => "string"})

    http().post(@contact_properties_endpoint, payload, headers(api_key))
    |> handle_response()
  end

  defp headers(api_key) do
    [
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    ]
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status}})
       when status in 200..299,
       do: :ok

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}),
    do: {:error, {:loops_api, status, body}}

  defp handle_response({:error, reason}), do: {:error, reason}

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
