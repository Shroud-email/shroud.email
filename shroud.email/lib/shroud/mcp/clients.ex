defmodule Shroud.Mcp.Clients do
  @moduledoc "Public MCP OAuth clients registered through configuration or RFC 7591."
  @behaviour Boruta.Oauth.Clients
  alias Shroud.{Mcp, Repo}
  import Boruta.Ecto.OauthMapper, only: [to_oauth_schema: 1]

  def metadata(id) when is_binary(id) do
    Mcp.clients()[id] ||
      case dynamic_client(id) do
        %Boruta.Ecto.Client{metadata: metadata, redirect_uris: redirects} ->
          Map.put(metadata, "redirect_uris", redirects)

        _ ->
          nil
      end
  end

  def metadata(_id), do: nil

  def register(params) when is_map(params) do
    redirects = params["redirect_uris"]
    name = Map.get(params, "client_name", "MCP client")

    cond do
      not (is_list(redirects) and length(redirects) in 1..10 and
               Enum.all?(redirects, &valid_redirect?/1)) ->
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

  defp dynamic_client(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Boruta.Ecto.Client{metadata: %{"mcp_dynamic" => true}} = client <-
           Repo.get(Boruta.Ecto.Client, uuid) do
      client
    else
      _ -> nil
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
    case Mcp.clients()[id] do
      %{"redirect_uris" => redirects} ->
        existing = Repo.get_by(Boruta.Ecto.Client, name: id)

        if existing && existing.redirect_uris == redirects &&
             existing.refresh_token_ttl == 90 * 86_400 do
          to_oauth_schema(existing)
        else
          Repo.insert!(
            public_client(id, redirects),
            on_conflict: {:replace, [:redirect_uris, :refresh_token_ttl]},
            conflict_target: :name
          )

          Repo.get_by!(Boruta.Ecto.Client, name: id) |> to_oauth_schema()
        end

      _ ->
        with {:ok, uuid} <- Ecto.UUID.cast(id),
             %Boruta.Ecto.Client{name: name} <- Repo.get(Boruta.Ecto.Client, uuid),
             true <- Map.has_key?(Mcp.clients(), name) do
          get_client(name)
        else
          _ ->
            case dynamic_client(id) do
              nil -> nil
              client -> to_oauth_schema(client)
            end
        end
    end
  end

  @impl true
  def authorized_scopes(_client), do: []
end
