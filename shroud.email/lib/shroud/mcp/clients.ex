defmodule Shroud.Mcp.Clients do
  @moduledoc "Boruta client registry backed by the configured MCP clients."
  @behaviour Boruta.Oauth.Clients
  alias Shroud.{Mcp, Repo}
  import Boruta.Ecto.OauthMapper, only: [to_oauth_schema: 1]

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
            },
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
          _ -> nil
        end
    end
  end

  @impl true
  def authorized_scopes(_client), do: []
end
