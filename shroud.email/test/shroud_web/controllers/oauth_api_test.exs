defmodule ShroudWeb.OAuthApiTest do
  use ShroudWeb.ConnCase, async: false
  import Shroud.OAuthFixtures
  import Shroud.AliasesFixtures
  alias Shroud.{OAuth, Repo}

  @mobile_id "3dab4011-1a87-453f-9b6d-c8e12a41c892"
  @chatgpt_id "7b705cee-124c-4abe-827f-d61c030c32c0"

  defp api_tokens(scopes, user \\ confirmed_user()) do
    callback = "https://app.shroud.email/oauth/callback"
    {params, verifier} = authorization_params(["aliases:read"])

    params =
      Map.merge(params, %{
        "client_id" => @mobile_id,
        "redirect_uri" => callback,
        "resource" => OAuth.resource(:api),
        "scope" => Enum.join(scopes, " ")
      })

    {:ok, code} = OAuth.authorize(user, params)

    exchange =
      Map.merge(params, %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => verifier
      })

    {:ok, tokens} = OAuth.exchange(exchange)
    %{tokens: tokens, user: user, params: params, exchange: exchange}
  end

  defp bearer(token), do: build_conn() |> put_req_header("authorization", "Bearer " <> token)

  test "browser consent and form token exchange work for API users" do
    user = confirmed_user()
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
    assert query["iss"] == OAuth.issuer()

    conn =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/oauth/token", URI.encode_query(%{exchange | "code" => query["code"]}))

    tokens = json_response(conn, 200)
    assert tokens["resource"] == OAuth.resource(:api)
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert bearer(tokens["access_token"]) |> get("/api/v1/me") |> json_response(200) ==
             %{"email" => user.email}
  end

  test "REST scope checks use narrowed token scopes, not the original consent" do
    %{tokens: tokens, params: params, user: user} = api_tokens(["aliases:read", "aliases:edit"])
    own = alias_fixture(%{user_id: user.id})

    {:ok, narrowed} =
      OAuth.exchange(%{
        "grant_type" => "refresh_token",
        "client_id" => params["client_id"],
        "resource" => OAuth.resource(:api),
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
      |> options(OAuth.resource(:api) <> "/aliases")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "access-control-allow-origin") == [origin]

    assert get_resp_header(conn, "access-control-allow-methods") == [
             "GET, POST, PATCH, DELETE, OPTIONS"
           ]

    assert get_resp_header(conn, "access-control-allow-headers") == [
             "Authorization, Content-Type, Accept"
           ]

    conn =
      bearer(tokens.access_token)
      |> put_req_header("origin", origin)
      |> get(OAuth.resource(:api) <> "/aliases")

    assert json_response(conn, 200)["email_aliases"] == []
    assert get_resp_header(conn, "access-control-allow-origin") == [origin]
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "registered API clients return only consented identity" do
    user = confirmed_user()
    %{tokens: tokens, params: params} = api_tokens(["profile:read", "aliases:read"], user)
    assert tokens.resource == OAuth.resource(:api)

    assert bearer(tokens.access_token) |> get("/api/v1/me") |> json_response(200) ==
             %{"email" => user.email}

    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> json_response(200)
    assert bearer(tokens.access_token) |> get(OAuth.resource(:mcp)) |> response(401)

    html =
      build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

    refute html =~ "id=\"unverified-client\""
    assert html =~ "View your email address"
    assert build_conn() |> log_in_user(user) |> get("/settings/security") |> response(200)

    refresh = %{
      "grant_type" => "refresh_token",
      "client_id" => params["client_id"],
      "resource" => OAuth.resource(:api),
      "refresh_token" => tokens.refresh_token
    }

    assert {:error, :invalid_grant} =
             OAuth.exchange(%{refresh | "resource" => OAuth.resource(:mcp)})

    assert {:ok, successor} = OAuth.exchange(refresh)
    assert {:error, :invalid_grant} = OAuth.exchange(refresh)
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
             OAuth.validate_authorization(%{params | "resource" => OAuth.resource(:api)})

    assert {:error, :invalid_request} =
             OAuth.validate_authorization(%{params | "scope" => "profile:read"})
  end

  test "revocation, expiration and account confirmation are checked on REST requests" do
    %{tokens: tokens, user: user} = api_tokens(["aliases:read"])
    [connection] = OAuth.list_connections(user)
    assert OAuth.revoke(user, connection.id)
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

  test "migrations provision official public clients and lookups do not create rows" do
    assert Repo.get!(Boruta.Ecto.Client, @mobile_id).metadata["registered"]
    assert Repo.get!(Boruta.Ecto.Client, @chatgpt_id).metadata["registered"]
    count = Repo.aggregate(Boruta.Ecto.Client, :count)
    client = OAuth.Clients.get_client(@mobile_id)
    assert client.id == @mobile_id
    assert client.pkce and client.public_refresh_token and client.public_revoke
    assert client.token_endpoint_auth_methods == ["none"]
    assert client.authorization_code_ttl == 300
    assert client.access_token_ttl == 3600
    assert client.refresh_token_ttl == 90 * 86_400
    assert OAuth.Clients.get_client(@mobile_id).id == client.id
    assert OAuth.Clients.metadata(String.upcase(@mobile_id))["registered"]

    assert OAuth.Clients.metadata(@mobile_id)["redirect_uris"] == [
             "https://app.shroud.email/oauth/callback"
           ]

    assert OAuth.Clients.get_client(Ecto.UUID.generate()) == nil
    assert Repo.aggregate(Boruta.Ecto.Client, :count) == count

    Repo.get!(Boruta.Ecto.Client, @mobile_id) |> Repo.delete!()
    assert OAuth.Clients.get_client(@mobile_id) == nil
    assert Repo.get(Boruta.Ecto.Client, @mobile_id) == nil
  end

  test "stored callbacks, name and security policy control official clients" do
    %{params: params, tokens: tokens, user: user} = api_tokens(["aliases:read"])
    callback = "https://client.example/approved-callback"

    Repo.get!(Boruta.Ecto.Client, @mobile_id)
    |> Ecto.Changeset.change(
      redirect_uris: [callback],
      access_token_ttl: 600,
      metadata: %{"name" => "Official app", "registered" => true, "resource_path" => "/api/v1"}
    )
    |> Repo.update!()

    assert OAuth.Clients.get_client(@mobile_id).access_token_ttl == 600
    assert OAuth.Clients.metadata(@mobile_id)["name"] == "Official app"
    assert [%{client_name: "Official app"}] = OAuth.list_connections(user)
    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> response(200)
    assert {:ok, _} = OAuth.validate_authorization(%{params | "redirect_uri" => callback})

    for callback <- [
          "https://evil.example/callback",
          params["redirect_uri"],
          callback <> "/",
          callback <> "?extra=1"
        ] do
      assert {:error, :invalid_request} =
               OAuth.validate_authorization(%{params | "redirect_uri" => callback})
    end
  end

  test "dynamic registrations cannot impersonate an official ID or approve themselves" do
    {:ok, registration} =
      OAuth.Clients.register(%{
        "client_id" => @mobile_id,
        "client_name" => "Shroud.email mobile",
        "redirect_uris" => ["https://app.shroud.email/oauth/callback"],
        "registered" => true,
        "resource_path" => "/api/v1",
        "metadata" => %{"registered" => true, "resource_path" => "/api/v1"}
      })

    refute registration.client_id == @mobile_id
    refute OAuth.Clients.metadata(registration.client_id)["registered"]
    assert OAuth.Clients.metadata(registration.client_id)["resource_path"] == "/mcp"

    user = confirmed_user()
    {params, _verifier} = authorization_params(["aliases:read"])

    params = %{
      params
      | "client_id" => registration.client_id,
        "redirect_uri" => "https://app.shroud.email/oauth/callback"
    }

    html =
      build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

    assert html =~ "id=\"unverified-client\""

    assert {:error, :invalid_request} =
             OAuth.validate_authorization(%{params | "resource" => OAuth.resource(:api)})
  end

  test "database registration approves clients without a predefined ID" do
    user = confirmed_user()
    {params, _verifier} = authorization_params(["aliases:read"])

    Repo.get!(Boruta.Ecto.Client, params["client_id"])
    |> Ecto.Changeset.change(
      metadata: %{"name" => "Approved app", "registered" => true, "resource_path" => "/api/v1"}
    )
    |> Repo.update!()

    params = %{params | "resource" => OAuth.resource(:api)}
    assert {:ok, %{registered: true, name: "Approved app"}} = OAuth.validate_authorization(params)

    html =
      build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

    refute html =~ "id=\"unverified-client\""
  end

  test "predefined ChatGPT uses only the official stable callback and MCP resource" do
    user = confirmed_user()
    {params, verifier} = authorization_params(["aliases:read"])

    params = %{
      params
      | "client_id" => @chatgpt_id,
        "redirect_uri" => "https://chatgpt.com/connector_platform_oauth_redirect"
    }

    conn = build_conn() |> log_in_user(user) |> get("/oauth/authorize", params)
    refute html_response(conn, 200) =~ "id=\"unverified-client\""
    assert {:ok, code} = OAuth.authorize(user, params)

    assert {:ok, tokens} =
             OAuth.exchange(
               Map.merge(params, %{
                 "grant_type" => "authorization_code",
                 "code" => code,
                 "code_verifier" => verifier
               })
             )

    assert tokens.resource == OAuth.resource(:mcp)

    assert {:ok, ^user} =
             OAuth.with_access(
               tokens.access_token,
               OAuth.resource(:mcp),
               "aliases:read",
               &{:ok, &1.user}
             )

    assert bearer(tokens.access_token) |> get("/api/v1/aliases") |> response(401)

    for callback <- [
          "https://chatgpt.com/connector/oauth/attacker",
          "https://evil.example/connector_platform_oauth_redirect"
        ] do
      assert {:error, :invalid_request} =
               OAuth.validate_authorization(%{params | "redirect_uri" => callback})
    end

    assert {:error, :invalid_request} =
             OAuth.validate_authorization(%{params | "resource" => OAuth.resource(:api)})
  end
end
