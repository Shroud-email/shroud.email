defmodule Shroud.Mcp do
  @moduledoc "Browser consent and resource-specific MCP and REST policies around Boruta's OAuth server."
  @behaviour Boruta.Oauth.AuthorizeApplication
  @behaviour Boruta.Oauth.TokenApplication
  @behaviour Boruta.Oauth.RevokeApplication
  import Ecto.Query
  alias Boruta.Ecto.Admin.Tokens
  alias Boruta.Oauth.Authorization.AccessToken
  alias Shroud.Mcp.{Clients, Connection}
  alias Shroud.Repo

  @permissions %{
    "aliases:read" => "View aliases",
    "aliases:create" => "Create aliases",
    "aliases:edit" => "Edit aliases",
    "domains:read" => "View custom domains"
  }

  def permissions, do: @permissions

  def api_permissions,
    do:
      Map.merge(@permissions, %{
        "aliases:delete" => "Delete aliases",
        "profile:read" => "View your account identity (including your email address)"
      })

  def permissions(resource) do
    cond do
      resource == resource() -> permissions()
      resource == api_resource() -> api_permissions()
      true -> %{}
    end
  end

  def required_scopes(scope) when scope in ["aliases:create", "aliases:edit", "aliases:delete"],
    do: [scope, "aliases:read"]

  def required_scopes(scope), do: [scope]

  def issuer, do: ShroudWeb.Endpoint.url()
  def resource, do: issuer() <> "/mcp"
  def api_resource, do: issuer() <> "/api/v1"

  def enabled?(user), do: FunWithFlags.enabled?(:chatgpt_integration, for: user)

  def enabled?(user, target),
    do: target == api_resource() or (target == resource() and enabled?(user))

  def validate_authorization(params) when is_map(params) do
    with %{
           "name" => name,
           "redirect_uris" => redirects,
           "resource_path" => path,
           "registered" => registered
         } <-
           Clients.metadata(params["client_id"]),
         true <- params["redirect_uri"] in redirects,
         true <- params["response_type"] == "code",
         true <- params["resource"] == issuer() <> path,
         true <- params["code_challenge_method"] == "S256",
         true <- not Map.has_key?(params, "request") and not Map.has_key?(params, "request_uri"),
         scope when is_binary(scope) <- params["scope"],
         scopes = String.split(scope, " ", trim: true) |> Enum.uniq(),
         true <- valid_scopes?(scope, params["resource"]),
         {:ok, _} <- Boruta.Oauth.preauthorize(oauth_conn(params), owner("consent"), __MODULE__) do
      {:ok,
       %{
         name: name,
         registered: registered,
         resource: params["resource"],
         scopes: scopes,
         redirect_uri: params["redirect_uri"]
       }}
    else
      _ -> {:error, :invalid_request}
    end
  end

  def authorize(user, params) do
    with {:ok, _} <- validate_authorization(params),
         true <- not is_nil(user.confirmed_at) and enabled?(user, params["resource"]) do
      conn = oauth_conn(params) |> Plug.Conn.assign(:mcp_user, user)
      Boruta.Oauth.authorize(conn, owner(to_string(user.id)), __MODULE__)
    else
      _ -> {:error, :invalid_request}
    end
  end

  @impl true
  def preauthorize_success(_conn, authorization), do: {:ok, authorization}
  @impl true
  def preauthorize_error(_conn, _error), do: {:error, :invalid_request}
  @impl true
  def authorize_error(_conn, _error), do: {:error, :invalid_request}

  @impl true
  def authorize_success(conn, response) do
    params = conn.assigns.mcp_params
    code = Repo.get_by!(Boruta.Ecto.Token, value: response.code)

    Repo.insert!(%Connection{
      user_id: conn.assigns.mcp_user.id,
      client_id: params["client_id"],
      resource: params["resource"],
      scopes: String.split(params["scope"], " ", trim: true) |> Enum.uniq(),
      code_id: code.id,
      expires_at: DateTime.add(now(), 90 * 86_400)
    })

    {:ok, response.code}
  end

  def exchange(%{"grant_type" => grant} = params)
      when grant in ["authorization_code", "refresh_token"] do
    credential = params[if(grant == "authorization_code", do: "code", else: "refresh_token")]

    if is_binary(credential) and byte_size(credential) in 1..1024,
      do: exchange_credential(grant, credential, params),
      else: {:error, :invalid_request}
  end

  def exchange(_params), do: {:error, :invalid_request}

  defp exchange_credential(grant, credential, params) do
    # Boruta creates the successor before revoking its predecessor. Serialize
    # exchanges for this connection and commit both operations with their link.
    transact(fn ->
      query =
        if grant == "authorization_code" do
          from c in Connection,
            join: t in Boruta.Ecto.Token,
            on: t.id == c.code_id,
            where: t.value == ^credential
        else
          token_connections(:refresh_token, credential)
        end

      with %Connection{} = connection <- Repo.one(from c in query, lock: "FOR UPDATE OF m0"),
           true <- valid_connection?(connection),
           true <- params["client_id"] == connection.client_id,
           true <- params["resource"] == connection.resource,
           true <- not Map.has_key?(params, "request") and not Map.has_key?(params, "request_uri") do
        cond do
          grant == "refresh_token" and reused_refresh_token?(credential) ->
            revoke(%{id: connection.user_id}, connection.id)
            {:error, :refresh_token_reused}

          Map.has_key?(params, "scope") and
              not valid_scopes?(params["scope"], connection.resource) ->
            {:error, :invalid_grant}

          true ->
            conn = oauth_conn(params) |> Plug.Conn.assign(:mcp_connection, connection)
            Boruta.Oauth.token(conn, __MODULE__)
        end
      else
        _ -> {:error, :invalid_grant}
      end
    end)
  end

  @impl true
  def token_error(_conn, _error), do: {:error, :invalid_grant}

  @impl true
  def token_success(conn, response) do
    token = Repo.get_by!(Boruta.Ecto.Token, value: response.access_token)

    Repo.insert_all("mcp_connection_tokens", [
      %{connection_id: conn.assigns.mcp_connection.id, token_id: Ecto.UUID.dump!(token.id)}
    ])

    {:ok,
     %{
       access_token: response.access_token,
       refresh_token: response.refresh_token,
       token_type: response.token_type,
       expires_in: response.expires_in,
       scope: response.token.scope,
       resource: conn.assigns.mcp_connection.resource
     }}
  end

  def with_access(token, scope, fun), do: with_access(token, resource(), scope, fun)

  def with_access(token, target, scope, fun) when is_binary(token) do
    with %Connection{} = connection <- Repo.one(token_connections(:value, token)),
         true <- connection.resource == target,
         true <- valid_connection?(connection),
         {:ok, oauth_token} <- AccessToken.authorize(value: token),
         true <- valid_scopes?(oauth_token.scope, target),
         true <- oauth_token.sub == to_string(connection.user_id) do
      if scope == nil or scope in String.split(oauth_token.scope, " ", trim: true),
        do: fun.(Repo.preload(connection, :user)),
        else: {:error, :insufficient_scope}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def with_access(_token, _target, _scope, _fun), do: {:error, :invalid_token}

  def list_connections(user) do
    Repo.all(
      from c in connections_query(user),
        left_join: client in Boruta.Ecto.Client,
        on: client.name == c.client_id,
        where: is_nil(c.revoked_at) and c.expires_at > ^now(),
        order_by: [desc: c.id],
        select: {c, client.metadata}
    )
    |> Enum.map(fn {connection, metadata} ->
      name =
        case Map.get(Clients.official_clients(), connection.client_id, metadata) do
          %{"name" => name} -> name
          _ -> "Disconnected client"
        end

      %{connection | client_name: name}
    end)
  end

  def revoke(user, id) do
    {count, _} =
      Repo.update_all(from(c in connections_query(user), where: c.id == ^id),
        set: [revoked_at: now()]
      )

    count == 1
  end

  def revoke_token(token, client_id)
      when is_binary(token) and byte_size(token) in 1..1024 and is_binary(client_id) do
    connection =
      Repo.one(token_connections(:value, token)) ||
        Repo.one(token_connections(:refresh_token, token))

    if connection && connection.client_id == client_id && Clients.metadata(client_id) != nil do
      Boruta.Oauth.revoke(oauth_conn(%{"client_id" => client_id, "token" => token}), __MODULE__)
      revoke(%{id: connection.user_id}, connection.id)
    end

    :ok
  end

  def revoke_token(_token, _client), do: :ok

  @impl true
  def revoke_success(_conn), do: :ok
  @impl true
  def revoke_error(_conn, _error), do: :ok

  def connections_query(user), do: from(c in Connection, where: c.user_id == ^user.id)

  def prune do
    Repo.delete_all(
      from c in Connection, where: c.expires_at <= ^now() or not is_nil(c.revoked_at)
    )

    # Retain expired access tokens while their refresh credentials can still be used.
    Tokens.delete_inactive_tokens(DateTime.add(now(), -90 * 86_400))
  end

  defp token_connections(field, token) do
    from c in Connection,
      join: link in "mcp_connection_tokens",
      on: link.connection_id == c.id,
      join: t in Boruta.Ecto.Token,
      on: t.id == type(link.token_id, Ecto.UUID),
      where: field(t, ^field) == ^token
  end

  defp valid_connection?(connection) do
    user = Repo.get(Shroud.Accounts.User, connection.user_id)
    metadata = Clients.metadata(connection.client_id)

    is_nil(connection.revoked_at) and DateTime.compare(connection.expires_at, now()) == :gt and
      metadata != nil and connection.resource == issuer() <> metadata["resource_path"] and
      valid_scopes?(Enum.join(connection.scopes, " "), connection.resource) and
      user != nil and user.confirmed_at != nil and enabled?(user, connection.resource)
  end

  defp transact(fun) do
    result =
      Repo.transaction(fn ->
        case fun.() do
          {:ok, result} -> result
          # Replay rejection must commit the connection's revocation.
          {:error, :refresh_token_reused} -> :refresh_token_reused
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, :refresh_token_reused} -> {:error, :invalid_grant}
      result -> result
    end
  end

  defp reused_refresh_token?(credential) do
    # Read after acquiring the connection lock so a waiting exchange sees rotation.
    token = Repo.get_by!(Boruta.Ecto.Token, refresh_token: credential)
    token.refresh_token_revoked_at != nil
  end

  defp valid_scopes?(scope, target) when is_binary(scope) do
    scopes = String.split(scope, " ", trim: true)

    scopes != [] and
      Enum.all?(scopes, fn permission ->
        Map.has_key?(permissions(target), permission) and
          Enum.all?(required_scopes(permission), &(&1 in scopes))
      end)
  end

  defp valid_scopes?(_scope, _target), do: false

  defp oauth_conn(params) do
    client = Clients.get_client(params["client_id"])
    translated = Map.put(params, "client_id", client.id)
    %Plug.Conn{query_params: translated, body_params: translated, assigns: %{mcp_params: params}}
  end

  defp owner(sub), do: %Boruta.Oauth.ResourceOwner{sub: sub}
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
