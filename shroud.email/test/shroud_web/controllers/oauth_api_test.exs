defmodule ShroudWeb.OAuthApiTest do
  use ShroudWeb.ConnCase, async: false
  import Shroud.McpFixtures
  import Shroud.AliasesFixtures
  alias Shroud.{Mcp, Repo}

  defp api_tokens(scopes, user \\ confirmed_user()) do
    id = Ecto.UUID.generate()
    callback = "https://app.shroud.email/oauth/callback"
    Mcp.Clients.provision!(id, "Shroud mobile", "/api/v1", [callback])
    {params, verifier} = authorization_params(["aliases:read"])

    params =
      Map.merge(params, %{
        "client_id" => id,
        "redirect_uri" => callback,
        "resource" => Mcp.api_resource(),
        "scope" => Enum.join(scopes, " ")
      })

    {:ok, code} = Mcp.authorize(user, params)

    exchange =
      Map.merge(params, %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => verifier
      })

    {:ok, tokens} = Mcp.exchange(exchange)
    %{tokens: tokens, user: user, params: params, exchange: exchange}
  end

  defp bearer(token), do: build_conn() |> put_req_header("authorization", "Bearer " <> token)

  test "browser consent and form token exchange work for unflagged API users" do
    user = confirmed_user()
    FunWithFlags.disable(:chatgpt_integration, for_actor: user)
    %{params: params, exchange: exchange} = api_tokens(["profile:read"], user)

    html =
      build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

    approval =
      html
      |> Floki.parse_document!()
      |> Floki.find("input[name=approval]")
      |> Floki.attribute("value")
      |> hd()

    callback =
      build_conn()
      |> log_in_user(user)
      |> post("/oauth/authorize", %{approval: approval, decision: "allow"})
      |> redirected_to()
      |> URI.parse()

    assert URI.to_string(%{callback | query: nil}) == "https://app.shroud.email/oauth/callback"
    query = URI.decode_query(callback.query)
    assert query["state"] == "user-supplied-state"
    assert query["iss"] == Mcp.issuer()

    conn =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/oauth/token", URI.encode_query(%{exchange | "code" => query["code"]}))

    tokens = json_response(conn, 200)
    assert tokens["resource"] == Mcp.api_resource()
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert bearer(tokens["access_token"]) |> get("/api/v1/me") |> json_response(200) ==
             %{"id" => to_string(user.id), "email" => user.email}
  end

  test "REST scope checks use narrowed token scopes, not the original consent" do
    %{tokens: tokens, params: params, user: user} = api_tokens(["aliases:read", "aliases:edit"])
    own = alias_fixture(%{user_id: user.id})

    {:ok, narrowed} =
      Mcp.exchange(%{
        "grant_type" => "refresh_token",
        "client_id" => params["client_id"],
        "resource" => Mcp.api_resource(),
        "refresh_token" => tokens.refresh_token,
        "scope" => "aliases:read"
      })

    assert bearer(narrowed.access_token) |> get("/api/v1/aliases/#{own.address}") |> response(200)

    assert bearer(narrowed.access_token)
           |> patch("/api/v1/aliases/#{own.address}", %{enabled: false})
           |> response(403)

    assert Repo.reload!(own).enabled
  end

  test "extensions can preflight and call REST endpoints without cookies" do
    %{tokens: tokens} = api_tokens(["aliases:read"])
    origin = "chrome-extension://example-extension"

    conn =
      build_conn()
      |> put_req_header("origin", origin)
      |> options(Mcp.api_resource() <> "/aliases")

    assert response(conn, 204) == ""

    assert get_resp_header(conn, "access-control-allow-methods") == [
             "GET, POST, PATCH, DELETE, OPTIONS"
           ]

    assert get_resp_header(conn, "access-control-allow-headers") == [
             "Authorization, Content-Type, Accept"
           ]

    conn =
      bearer(tokens.access_token)
      |> put_req_header("origin", origin)
      |> get(Mcp.api_resource() <> "/aliases")

    assert json_response(conn, 200)["email_aliases"] == []
    assert get_resp_header(conn, "access-control-allow-origin") == [origin]
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "registered API clients work without the MCP flag and return only consented identity" do
    user = confirmed_user()
    FunWithFlags.disable(:chatgpt_integration, for_actor: user)
    %{tokens: tokens, params: params} = api_tokens(["profile:read", "aliases:read"], user)
    assert tokens.resource == Mcp.api_resource()

    assert bearer(tokens.access_token) |> get("/api/v1/me") |> json_response(200) ==
             %{"id" => to_string(user.id), "email" => user.email}

    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> json_response(200)
    assert bearer(tokens.access_token) |> get(Mcp.resource()) |> response(401)

    html =
      build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

    refute html =~ "id=\"unverified-client\""
    assert html =~ "View your account identity"
    assert build_conn() |> log_in_user(user) |> get("/settings/connections") |> response(200)

    refresh = %{
      "grant_type" => "refresh_token",
      "client_id" => params["client_id"],
      "resource" => Mcp.api_resource(),
      "refresh_token" => tokens.refresh_token
    }

    assert {:error, :invalid_grant} = Mcp.exchange(%{refresh | "resource" => Mcp.resource()})
    assert {:ok, successor} = Mcp.exchange(refresh)
    assert {:error, :invalid_grant} = Mcp.exchange(refresh)
    assert bearer(successor.access_token) |> get("/api/v1/aliases") |> response(401)
  end

  test "read tokens cannot mutate aliases or read identity or domains" do
    %{tokens: tokens, user: user} = api_tokens(["aliases:read"])
    alias = alias_fixture(%{user_id: user.id})

    for {method, path, params} <- [
          {:post, "/api/v1/aliases", %{}},
          {:patch, "/api/v1/aliases/#{alias.address}", %{enabled: false}},
          {:delete, "/api/v1/aliases/#{alias.address}", %{}},
          {:get, "/api/v1/me", %{}},
          {:get, "/api/v1/domains", %{}}
        ] do
      conn = dispatch(bearer(tokens.access_token), ShroudWeb.Endpoint, method, path, params)
      assert json_response(conn, 403)["error"] == "insufficient_scope"
      assert get_resp_header(conn, "www-authenticate") |> hd() =~ "scope="
    end

    assert Repo.reload!(alias).enabled
    assert Repo.reload!(alias).deleted_at == nil
  end

  test "edit and delete permissions are separate and account ownership is enforced" do
    %{tokens: edit, user: user} = api_tokens(["aliases:read", "aliases:edit"])
    own = alias_fixture(%{user_id: user.id})
    other = alias_fixture(%{user_id: confirmed_user().id})

    assert bearer(edit.access_token)
           |> patch("/api/v1/aliases/#{own.address}", %{enabled: false})
           |> json_response(200)

    assert bearer(edit.access_token)
           |> patch("/api/v1/aliases/#{other.address}", %{enabled: false})
           |> response(404)

    assert bearer(edit.access_token) |> delete("/api/v1/aliases/#{own.address}") |> response(403)
    %{tokens: delete} = api_tokens(["aliases:read", "aliases:delete"], user)

    assert bearer(delete.access_token)
           |> delete("/api/v1/aliases/#{own.address}")
           |> response(204)
  end

  test "MCP clients and tokens cannot obtain REST access" do
    %{tokens: tokens} = connection_fixture(["aliases:read"])
    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> response(401)
    {params, _} = authorization_params(["aliases:read"])

    assert {:error, :invalid_request} =
             Mcp.validate_authorization(%{params | "resource" => Mcp.api_resource()})

    assert {:error, :invalid_request} =
             Mcp.validate_authorization(%{params | "scope" => "profile:read"})
  end

  test "revocation, expiration and account confirmation are checked on REST requests" do
    %{tokens: tokens, user: user} = api_tokens(["aliases:read"])
    [connection] = Mcp.list_connections(user)
    assert Mcp.revoke(user, connection.id)
    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> response(401)

    %{tokens: tokens} = api_tokens(["aliases:read"], user)

    Repo.get_by!(Boruta.Ecto.Token, value: tokens.access_token)
    |> Ecto.Changeset.change(expires_at: 0)
    |> Repo.update!()

    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> response(401)

    %{tokens: tokens} = api_tokens(["aliases:read"], user)
    user |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()
    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> response(401)
  end

  test "provisioning is idempotent and cannot replace an unrelated client" do
    id = Ecto.UUID.generate()
    callback = "https://app.shroud.email/oauth/callback"
    first = Mcp.Clients.provision!(id, "Mobile", "/api/v1", [callback])
    assert Mcp.Clients.provision!(id, "Mobile", "/api/v1", [callback]).id == first.id
    client = Mcp.Clients.get_client(id)
    assert client.pkce and client.public_refresh_token and client.public_revoke
    assert Mcp.Clients.metadata(id)["resource_path"] == "/api/v1"

    assert_raise ArgumentError, fn ->
      Mcp.Clients.provision!(client_fixture(), "Impostor", "/api/v1", [callback])
    end

    assert_raise ArgumentError, fn ->
      Mcp.Clients.provision!(id, "Mobile", "/api/v1", ["https://evil.example/#fragment"])
    end
  end
end
