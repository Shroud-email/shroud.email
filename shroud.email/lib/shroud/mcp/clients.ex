defmodule Shroud.Mcp.Clients do
  @moduledoc "Official public OAuth clients and dynamic MCP clients registered through RFC 7591."
  @behaviour Boruta.Oauth.Clients
  alias Shroud.Repo
  import Boruta.Ecto.OauthMapper, only: [to_oauth_schema: 1]

  # Official registrations use stable IDs and exact callbacks on every instance.
  @official_clients %{
    "3dab4011-1a87-453f-9b6d-c8e12a41c892" => %{
      "name" => "Shroud.email mobile",
      "resource_path" => "/api/v1",
      "registered" => true,
      "redirect_uris" => ["https://app.shroud.email/oauth/callback"]
    },
    "7b705cee-124c-4abe-827f-d61c030c32c0" => %{
      "name" => "ChatGPT",
      "resource_path" => "/mcp",
      "registered" => true,
      "redirect_uris" => ["https://chatgpt.com/connector_platform_oauth_redirect"]
    }
  }

  def official_clients, do: @official_clients

  def metadata(id) when is_binary(id) do
    case find_client(id) do
      %Boruta.Ecto.Client{id: uuid, metadata: metadata, redirect_uris: redirects} ->
        metadata
        |> Map.put("redirect_uris", redirects)
        |> Map.put_new("resource_path", "/mcp")
        |> Map.put("registered", Map.has_key?(@official_clients, uuid))

      _ ->
        nil
    end
  end

  def metadata(_id), do: nil

  def register(params) when is_map(params) do
    redirects = params["redirect_uris"]
    name = Map.get(params, "client_name", "MCP client")

    cond do
      not valid_redirects?(redirects) ->
        {:error, :invalid_redirect_uri}

      not valid_name?(name) or
        Map.get(params, "token_endpoint_auth_method", "none") != "none" or
        Map.get(params, "response_types", ["code"]) != ["code"] or
          not valid_grants?(Map.get(params, "grant_types", ["authorization_code"])) ->
        {:error, :invalid_client_metadata}

      true ->
        id = Ecto.UUID.generate()

        client =
          public_client(id, redirects)
          |> Map.put(:id, id)
          |> Map.put(:metadata, %{"name" => name, "mcp_dynamic" => true})
          |> Repo.insert!()

        {:ok,
         %{
           client_id: id,
           client_id_issued_at: DateTime.to_unix(client.inserted_at),
           client_name: name,
           redirect_uris: redirects,
           token_endpoint_auth_method: "none",
           response_types: ["code"],
           grant_types: ["authorization_code", "refresh_token"]
         }}
    end
  end

  def register(_params), do: {:error, :invalid_client_metadata}

  defp valid_redirects?(redirects) when is_list(redirects),
    do: length(redirects) in 1..10 and Enum.all?(redirects, &valid_redirect?/1)

  defp valid_redirects?(_redirects), do: false

  defp valid_name?(name) when is_binary(name) and byte_size(name) in 1..255,
    do: String.trim(name) != ""

  defp valid_name?(_name), do: false

  defp valid_grants?(grants) when is_list(grants),
    do:
      "authorization_code" in grants and
        Enum.all?(grants, &(&1 in ["authorization_code", "refresh_token"]))

  defp valid_grants?(_grants), do: false

  defp valid_redirect?(uri) when is_binary(uri) and byte_size(uri) in 1..2048 do
    match?(
      {:ok, %URI{scheme: scheme, host: host, port: port, userinfo: nil, fragment: nil}}
      when is_binary(host) and host != "" and port in 1..65_535 and
             (scheme == "https" or
                (scheme == "http" and host in ["localhost", "127.0.0.1", "::1"])),
      URI.new(uri)
    ) and not String.match?(uri, ~r/[\x00-\x20\x7f]/)
  end

  defp valid_redirect?(_uri), do: false

  defp find_client(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case @official_clients[uuid] do
          nil ->
            case Repo.get(Boruta.Ecto.Client, uuid) do
              %Boruta.Ecto.Client{metadata: %{"mcp_dynamic" => true}} = client -> client
              _ -> nil
            end

          metadata ->
            client =
              public_client(uuid, metadata["redirect_uris"])
              |> Map.put(:id, uuid)
              |> Map.put(:metadata, Map.delete(metadata, "redirect_uris"))
              |> Map.put(:authorized_scopes, [])

            # Boruta's code/token foreign keys require a row; policy comes from the catalog.
            if is_nil(Repo.get(Boruta.Ecto.Client, uuid)) do
              Repo.insert!(client, on_conflict: :nothing, conflict_target: [:id])
            end

            client
        end

      _ ->
        nil
    end
  end

  defp public_client(id, redirects) do
    %Boruta.Ecto.Client{
      name: id,
      secret: "",
      private_key: "",
      redirect_uris: redirects,
      supported_grant_types: ["authorization_code", "refresh_token", "revoke"],
      pkce: true,
      public_refresh_token: true,
      public_revoke: true,
      authorization_code_ttl: 300,
      access_token_ttl: 3600,
      refresh_token_ttl: 90 * 86_400,
      token_endpoint_auth_methods: ["none"]
    }
  end

  @impl true
  def get_client(id) do
    case find_client(id) do
      nil -> nil
      client -> to_oauth_schema(client)
    end
  end

  @impl true
  def authorized_scopes(_client), do: []
end
