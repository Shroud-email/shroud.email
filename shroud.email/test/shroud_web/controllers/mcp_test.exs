defmodule ShroudWeb.McpTest do
  use ShroudWeb.ConnCase, async: false
  import Shroud.{OAuthFixtures, AliasesFixtures, DomainFixtures}
  import Phoenix.LiveViewTest
  alias ExMCP.Content.SchemaPolicy
  alias Shroud.{Accounts, Aliases, OAuth, Repo}
  alias Shroud.Mcp.Tools

  test "output schemas accept structured errors without weakening success validation" do
    for tool <- Tools.list() do
      for error <- [
            %{"error_code" => "INVALID_ARGUMENT"},
            %{"error_code" => "ALIAS_ALREADY_EXISTS", "address" => "shop@example.com"},
            %{"error_code" => "INSUFFICIENT_SCOPE", "required_scopes" => ["aliases:read"]}
          ] do
        assert :ok = SchemaPolicy.validate(error, tool.outputSchema)
      end

      for invalid <- [
            %{},
            %{"address" => "shop@example.com"},
            %{"error_code" => 123},
            %{"error_code" => "INVALID_ARGUMENT", "unexpected" => true},
            %{"error_code" => "INSUFFICIENT_SCOPE", "required_scopes" => "aliases:read"}
          ] do
        assert {:error, _} = SchemaPolicy.validate(invalid, tool.outputSchema)
      end
    end
  end

  test "integral JSON floats paginate like integers and fractional values remain invalid" do
    %{user: user, tokens: tokens} = connection_fixture()

    aliases =
      for i <- 1..5 do
        entry = alias_fixture(%{user_id: user.id, title: "Store #{i}"})
        entry |> Ecto.Changeset.change(inserted_at: ~N[2026-01-01 00:00:00]) |> Repo.update!()
      end

    integer = tool(tokens, "list_aliases", %{limit: 2, page: 2})["structuredContent"]

    assert Enum.map(integer["aliases"], & &1["address"]) == [
             Enum.at(aliases, 2).address,
             Enum.at(aliases, 1).address
           ]

    assert integer["has_more"]

    for args <- [%{limit: 2.0, page: 2}, %{limit: 2, page: 2.0}, %{limit: 2.0, page: 2.0}] do
      assert tool(tokens, "list_aliases", args)["structuredContent"] == integer
    end

    assert tool(tokens, "list_aliases", %{limit: 1.0})["structuredContent"] ==
             tool(tokens, "list_aliases", %{limit: 1})["structuredContent"]

    custom_domain_fixture(%{user_id: user.id})

    assert tool(tokens, "list_verified_domains", %{page: 1.0})["structuredContent"] ==
             tool(tokens, "list_verified_domains", %{page: 1})["structuredContent"]

    for {name, args} <- [
          {"list_aliases", %{limit: 1.5}},
          {"list_aliases", %{page: 1.5}},
          {"list_verified_domains", %{page: 1.5}}
        ] do
      result = tool(tokens, name, args)
      assert result["isError"]
      assert result["structuredContent"]["error_code"] == "INVALID_ARGUMENT"
    end
  end

  test "HTTP authentication and rate-limit failures return machine-readable codes" do
    assert rpc(nil, "tools/list") |> json_response(401) == %{
             "error_code" => "AUTHENTICATION_REQUIRED",
             "error" => "Authentication required"
           }

    %{user: user, tokens: tokens} = connection_fixture()
    for _ <- 1..120, do: Shroud.RateLimit.check(:api, {:account, user.id})
    conn = rpc(tokens.access_token, "tools/list")
    assert json_response(conn, 429)["error_code"] == "RATE_LIMITED"
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) in 1..60
  end

  test "page pagination follows creation time and ID with search, status and configurable limits" do
    %{user: user, tokens: tokens} = connection_fixture()
    newer_id = alias_fixture(%{user_id: user.id, title: "Store old", notes: "Receipts"})
    first_tie = alias_fixture(%{user_id: user.id, title: "Store tie", notes: "Receipts"})
    last_tie = alias_fixture(%{user_id: user.id, title: "Store tie", notes: "Receipts"})
    oldest = alias_fixture(%{user_id: user.id, title: "Store oldest", notes: "Receipts"})

    for {entry, timestamp} <- [
          {newer_id, ~N[2026-01-02 00:00:00]},
          {first_tie, ~N[2026-01-03 00:00:00]},
          {last_tie, ~N[2026-01-03 00:00:00]},
          {oldest, ~N[2026-01-01 00:00:00]}
        ] do
      entry |> Ecto.Changeset.change(inserted_at: timestamp) |> Repo.update!()
    end

    alias_fixture(%{user_id: user.id, title: "Store", notes: "Receipts", enabled: false})
    alias_fixture(%{user_id: confirmed_user().id, title: "Store", notes: "Receipts"})
    filters = %{search: "tOrE ceip", enabled: true, limit: 1}
    first = tool(tokens, "list_aliases", filters)["structuredContent"]
    assert Enum.map(first["aliases"], & &1["address"]) == [last_tie.address]
    assert hd(first["aliases"])["created_at"] == "2026-01-03T00:00:00Z"
    assert first["has_more"]

    second = tool(tokens, "list_aliases", Map.put(filters, :page, 2))["structuredContent"]
    assert Enum.map(second["aliases"], & &1["address"]) == [first_tie.address]
    assert second["has_more"]

    final =
      tool(tokens, "list_aliases", %{filters | limit: 2} |> Map.put(:page, 2))[
        "structuredContent"
      ]

    assert Enum.map(final["aliases"], & &1["address"]) == [newer_id.address, oldest.address]
    refute final["has_more"]
    refute Map.has_key?(final, "next_cursor")

    assert length(tool(tokens, "list_aliases", %{limit: 100})["structuredContent"]["aliases"]) ==
             5

    for args <- [
          %{limit: 0},
          %{limit: 101},
          %{limit: 1.5},
          %{cursor: "unsupported"}
        ] do
      result = tool(tokens, "list_aliases", args)
      assert result["isError"]
      assert result["structuredContent"] == %{"error_code" => "INVALID_ARGUMENT"}
    end
  end

  test "duplicate disabled aliases return their normalized address and a specific error" do
    %{user: user, tokens: tokens} = connection_fixture()
    domain = custom_domain_fixture(%{user_id: user.id})
    args = %{title: "Shop", domain: domain.domain, local_part: "shop"}
    created = tool(tokens, "create_alias", args)["structuredContent"]
    tool(tokens, "edit_alias", %{address: created["address"], enabled: false})
    result = tool(tokens, "create_alias", %{args | local_part: "SHOP"})
    assert result["isError"]

    assert result["structuredContent"] == %{
             "error_code" => "ALIAS_ALREADY_EXISTS",
             "address" => created["address"]
           }

    assert hd(result["content"])["text"] ==
             "This alias address already exists, including as a disabled alias. Choose a different local part or edit the existing alias."
  end

  test "discovery advertises PKCE, issuer identification, resource and bounded scopes" do
    metadata =
      build_conn() |> get("/.well-known/oauth-authorization-server") |> json_response(200)

    assert metadata["issuer"] == OAuth.issuer()
    assert metadata["authorization_response_iss_parameter_supported"]
    assert metadata["code_challenge_methods_supported"] == ["S256"]
    assert metadata["token_endpoint_auth_methods_supported"] == ["none"]
    assert metadata["registration_endpoint"] == OAuth.issuer() <> "/oauth/register"

    resource =
      build_conn() |> get("/.well-known/oauth-protected-resource/mcp") |> json_response(200)

    assert resource["resource"] == OAuth.resource(:mcp)
    assert resource["authorization_servers"] == [OAuth.issuer()]
    refute "email" in resource["scopes_supported"]
  end

  test "login preserves authorization return-to and no grant is created before consent" do
    {params, _} = authorization_params()
    conn = build_conn() |> get("/oauth/authorize", params)
    assert redirected_to(conn) == "/users/log_in"
    assert get_session(conn, :user_return_to) |> String.starts_with?("/oauth/authorize?")
    assert Repo.aggregate(OAuth.Connection, :count) == 0
  end

  test "browser consent shows only requested permissions and binds the account and signed request" do
    user = confirmed_user()
    {params, verifier} = authorization_params(["aliases:read", "aliases:create"])
    conn = build_conn() |> log_in_user(user) |> get("/oauth/authorize", params)
    html = html_response(conn, 200)
    document = LazyHTML.from_document(html)
    assert LazyHTML.text(document) =~ "Access expires after 90 days."

    assert LazyHTML.query(document, "#unverified-client") |> LazyHTML.text() =~
             "Shroud.email has not verified this app's identity. Only connect an app you trust."

    assert LazyHTML.query(document, "#unverified-client") |> LazyHTML.text() =~
             params["redirect_uri"]

    refute LazyHTML.text(document) =~ "delete aliases"
    assert LazyHTML.query(document, "#connection-permissions li") |> Enum.count() == 2
    assert LazyHTML.query(document, "script") |> LazyHTML.attribute("src") == ["/assets/app.js"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    approval = hidden(html, "approval")
    assert Repo.aggregate(OAuth.Connection, :count) == 0

    wrong_user =
      build_conn()
      |> log_in_user(confirmed_user())
      |> post("/oauth/authorize", %{approval: approval, decision: "allow"})

    assert response(wrong_user, 400)

    tampered =
      build_conn()
      |> log_in_user(user)
      |> post("/oauth/authorize", %{approval: approval <> "x", decision: "allow"})

    assert response(tampered, 400)

    allowed =
      build_conn()
      |> log_in_user(user)
      |> post("/oauth/authorize", %{approval: approval, decision: "allow", scope: "aliases:edit"})

    callback = allowed |> redirected_to() |> URI.parse()
    assert callback.host == "client.example"
    query = URI.decode_query(callback.query)
    assert query["state"] == params["state"]
    assert query["iss"] == OAuth.issuer()

    conn =
      build_conn()
      |> post(
        "/oauth/token",
        Map.merge(params, %{
          "grant_type" => "authorization_code",
          "code" => query["code"],
          "code_verifier" => verifier
        })
      )

    tokens = json_response(conn, 200)
    assert tokens["scope"] == "aliases:read aliases:create"
    assert tokens["expires_in"] in 3599..3600
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "consent uses short permission labels without changing scopes" do
    user = confirmed_user()

    for {scopes, expected} <- [
          {["aliases:read", "aliases:create"], ["View aliases", "Create aliases"]},
          {["aliases:read", "aliases:edit"], ["View aliases", "Edit aliases"]},
          {["aliases:read", "aliases:create", "aliases:edit", "domains:read"],
           ["View aliases", "Create aliases", "Edit aliases", "View custom domains"]}
        ] do
      {params, _} = authorization_params(scopes)
      conn = build_conn() |> log_in_user(user) |> get("/oauth/authorize", params)
      html = html_response(conn, 200)

      labels =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#connection-permissions li")
        |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))

      assert labels == expected

      build_conn()
      |> log_in_user(user)
      |> post("/oauth/authorize", %{approval: hidden(html, "approval"), decision: "allow"})
      |> redirected_to()

      assert hd(OAuth.list_connections(user)).scopes == scopes
    end
  end

  test "denial preserves issuer/state without creating a grant; invalid callback never redirects" do
    user = confirmed_user()
    {params, _} = authorization_params()

    consent =
      build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

    denied =
      build_conn()
      |> log_in_user(user)
      |> post("/oauth/authorize", %{approval: hidden(consent, "approval"), decision: "deny"})

    query = denied |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert query == %{
             "state" => params["state"],
             "iss" => OAuth.issuer(),
             "error" => "access_denied"
           }

    assert Repo.aggregate(OAuth.Connection, :count) == 0

    conn =
      build_conn()
      |> log_in_user(user)
      |> get("/oauth/authorize", Map.put(params, "redirect_uri", "https://evil.example/callback"))

    assert response(conn, 400)
    assert get_resp_header(conn, "location") == []
  end

  test "real CSRF protection prevents consent without browser form tokens" do
    user = confirmed_user()

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      build_conn()
      |> log_in_user(user)
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/oauth/authorize", %{approval: "anything", decision: "allow"})
    end
  end

  test "bearer-only MCP auth rejects browser sessions, REST tokens and refresh tokens" do
    %{user: user, tokens: tokens} = connection_fixture()
    assert rpc(nil, "tools/list") |> response(401)

    conn =
      build_conn()
      |> log_in_user(user)
      |> put_req_header("origin", "https://agent.example")
      |> get(OAuth.resource(:mcp))

    assert response(conn, 401)

    assert get_resp_header(conn, "www-authenticate")
           |> hd()
           |> String.contains?("resource_metadata=")

    rest_token = Accounts.generate_user_session_token(user) |> Base.encode64()
    assert rpc(rest_token, "tools/list") |> response(401)
    assert rpc(tokens.refresh_token, "tools/list") |> response(401)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> tokens.access_token)
      |> get("/api/v1/aliases")

    assert json_response(conn, 401) == %{"error" => "Invalid token"}
  end

  test "bearer scheme accepts case variants and multiple spaces but not malformed credentials" do
    %{tokens: tokens} = connection_fixture()

    for scheme <- ["bearer ", "bEaReR ", "Bearer    "] do
      conn =
        build_conn()
        |> put_req_header("authorization", scheme <> tokens.access_token)
        |> get(OAuth.resource(:mcp))

      assert response(conn, 405)
    end

    for header <- [
          "Basic " <> tokens.access_token,
          "Bearer" <> tokens.access_token,
          "Bearer " <> tokens.access_token <> " extra",
          "Bearer " <> String.duplicate("x", 1025)
        ] do
      assert build_conn()
             |> put_req_header("authorization", header)
             |> get(OAuth.resource(:mcp))
             |> response(401)
    end
  end

  test "any browser origin receives preflight, challenge and MCP response CORS headers" do
    %{tokens: tokens} = connection_fixture()

    for origin <- [
          OAuth.issuer(),
          "https://chatgpt.com",
          "https://agent.example",
          "http://localhost:5173",
          "null"
        ] do
      preflight =
        build_conn()
        |> put_req_header("origin", origin)
        |> put_req_header("access-control-request-method", "POST")
        |> put_req_header(
          "access-control-request-headers",
          "authorization, mcp-protocol-version, mcp-method, mcp-name"
        )
        |> options(OAuth.resource(:mcp))

      assert response(preflight, 204) == ""
      assert get_resp_header(preflight, "access-control-allow-origin") == [origin]

      assert get_resp_header(preflight, "access-control-allow-methods") == [
               "POST, DELETE, OPTIONS"
             ]

      assert get_resp_header(preflight, "access-control-allow-headers") |> hd() =~ "Authorization"
      assert get_resp_header(preflight, "access-control-allow-headers") |> hd() =~ "MCP-Method"
      assert get_resp_header(preflight, "access-control-allow-headers") |> hd() =~ "MCP-Name"
      assert get_resp_header(preflight, "access-control-allow-credentials") == []

      challenge = rpc(nil, "tools/list", %{}, [{"origin", origin}])
      assert response(challenge, 401)
      assert get_resp_header(challenge, "access-control-allow-origin") == [origin]

      assert get_resp_header(challenge, "access-control-expose-headers") |> hd() =~
               "WWW-Authenticate"

      success = rpc(tokens.access_token, "tools/list", %{}, [{"origin", origin}])
      assert json_response(success, 200)["result"]["tools"] != []
      assert get_resp_header(success, "access-control-allow-origin") == [origin]
      assert get_resp_header(success, "vary") == ["Origin"]
    end

    for path <- ["/mcp", "/mcp/nested"] do
      preflight =
        build_conn()
        |> put_req_header("origin", "https://agent.example")
        |> options(OAuth.issuer() <> path)

      assert response(preflight, 204) == ""

      assert get_resp_header(preflight, "access-control-allow-origin") == [
               "https://agent.example"
             ]
    end

    bad_host = %{build_conn() | host: "evil.example"}

    assert bad_host
           |> put_req_header("origin", "https://chatgpt.com")
           |> options("/mcp")
           |> response(403)
  end

  test "initialization, notifications, tool listing and metadata survive the SDK transport" do
    %{tokens: tokens} = connection_fixture()

    result =
      rpc(tokens.access_token, "initialize", %{
        protocolVersion: "2025-11-25",
        capabilities: %{},
        clientInfo: %{name: "test", version: "1"}
      })
      |> json_response(200)

    assert result["result"]["protocolVersion"] == "2025-11-25"
    assert result["result"]["capabilities"]["tools"] == %{"listChanged" => false}
    assert result["result"]["serverInfo"]["name"] == "shroud-email"

    assert result["result"]["instructions"] =~
             "Manage email aliases and verified domains in Shroud.email."

    assert result["result"]["instructions"] =~ "Aliases are anonymous email addresses"

    tools =
      rpc(tokens.access_token, "tools/list") |> json_response(200) |> get_in(["result", "tools"])

    assert Enum.map(tools, & &1["name"]) |> Enum.sort() ==
             ~w(create_alias edit_alias get_alias list_aliases list_verified_domains)

    for tool <- tools do
      assert tool["inputSchema"]["additionalProperties"] == false
      assert tool["outputSchema"]["type"] == "object"
      refute Jason.encode!(tool) =~ "label"
      refute Map.has_key?(tool, "securitySchemes")
      refute Map.has_key?(tool["_meta"] || %{}, "securitySchemes")
      assert tool["annotations"]["openWorldHint"] == false
    end

    assert Enum.find(tools, &(&1["name"] == "edit_alias"))["annotations"]["destructiveHint"]

    for name <- ~w(list_aliases list_verified_domains) do
      page = Enum.find(tools, &(&1["name"] == name))["inputSchema"]["properties"]["page"]
      refute Map.has_key?(page, "maximum")
    end

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> tokens.access_token)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-session-id", session_id(tokens.access_token))
      |> post(
        OAuth.resource(:mcp),
        Jason.encode!(%{jsonrpc: "2.0", method: "notifications/initialized"})
      )

    assert response(conn, 202) == ""
  end

  test "a reused SDK session cannot carry another account's authority" do
    %{user: owner, tokens: first} = connection_fixture()
    %{tokens: second} = connection_fixture(["aliases:read"])
    own = alias_fixture(%{user_id: owner.id, title: "Owner only"})

    result =
      rpc(
        second.access_token,
        "tools/call",
        %{name: "get_alias", arguments: %{address: own.address}},
        [
          {"mcp-session-id", session_id(first.access_token)}
        ]
      )
      |> json_response(200)

    assert result["result"]["isError"]
    refute Jason.encode!(result) =~ "Owner only"
  end

  test "modern discovery and calls work without a session and reject a rebinding host" do
    %{user: user, tokens: tokens} = connection_fixture()
    own = alias_fixture(%{user_id: user.id, title: "Modern"})
    headers = [{"mcp-protocol-version", "2026-07-28"}]
    discovery = rpc(tokens.access_token, "server/discover", %{}, headers)

    assert json_response(discovery, 200)["result"]["_meta"]["io.modelcontextprotocol/serverInfo"][
             "name"
           ] == "shroud-email"

    assert get_resp_header(discovery, "mcp-session-id") == []

    result =
      rpc(
        tokens.access_token,
        "tools/call",
        %{name: "get_alias", arguments: %{address: own.address}},
        headers
      )

    assert json_response(result, 200)["result"]["structuredContent"]["title"] == "Modern"

    conn = build_conn() |> put_req_header("authorization", "Bearer " <> tokens.access_token)
    assert conn |> get("https://evil.example/mcp") |> response(403) == "Forbidden host"
  end

  test "listing returns full alias details, paginates and excludes foreign and deleted aliases" do
    %{user: user, tokens: tokens} = connection_fixture()

    expected =
      for i <- 1..11 do
        notes = if i == 11, do: nil, else: "Receipt #{i}"
        alias = alias_fixture(%{user_id: user.id, title: "Store #{i}", notes: notes})

        %{
          "address" => alias.address,
          "title" => "Store #{i}",
          "notes" => notes,
          "created_at" => NaiveDateTime.to_iso8601(alias.inserted_at) <> "Z",
          "enabled" => true
        }
      end

    alias_fixture(%{user_id: confirmed_user().id, title: "Store foreign"})
    deleted = alias_fixture(%{user_id: user.id, title: "Store deleted"})
    Aliases.delete_email_alias(deleted.id)

    first = tool(tokens, "list_aliases", %{})
    assert length(first["structuredContent"]["aliases"]) == 10
    assert first["structuredContent"]["has_more"]
    second = tool(tokens, "list_aliases", %{page: 2})
    assert length(second["structuredContent"]["aliases"]) == 1
    refute second["structuredContent"]["has_more"]

    assert first["structuredContent"]["aliases"] ++ second["structuredContent"]["aliases"] ==
             Enum.reverse(expected)

    refute Jason.encode!(first) =~ user.email

    for page <- [3, 1001] do
      assert tool(tokens, "list_aliases", %{page: page})["structuredContent"] == %{
               "aliases" => [],
               "has_more" => false
             }
    end

    for search <- ["", "   "] do
      assert tool(tokens, "list_aliases", %{search: search})["structuredContent"] ==
               first["structuredContent"]
    end
  end

  test "listing searches address, title and notes with literal multi-term and enabled filters" do
    %{user: user, tokens: tokens} = connection_fixture()
    enabled = alias_fixture(%{user_id: user.id, title: "Store", notes: "Receipt"})

    disabled =
      alias_fixture(%{
        user_id: user.id,
        title: "Unrelated",
        notes: "Store 100%_\\",
        enabled: false
      })

    foreign = alias_fixture(%{user_id: confirmed_user().id, title: "Store"})

    assert tool(tokens, "list_aliases", %{search: "STORE", enabled: true})["structuredContent"] ==
             %{
               "aliases" => [
                 %{
                   "address" => enabled.address,
                   "title" => "Store",
                   "notes" => "Receipt",
                   "created_at" => NaiveDateTime.to_iso8601(enabled.inserted_at) <> "Z",
                   "enabled" => true
                 }
               ],
               "has_more" => false
             }

    assert tool(tokens, "list_aliases", %{enabled: false})["structuredContent"] == %{
             "aliases" => [
               %{
                 "address" => disabled.address,
                 "title" => "Unrelated",
                 "notes" => "Store 100%_\\",
                 "created_at" => NaiveDateTime.to_iso8601(disabled.inserted_at) <> "Z",
                 "enabled" => false
               }
             ],
             "has_more" => false
           }

    for search <- [String.upcase(disabled.address), "UNRELATED STORE", "%_\\"] do
      assert tool(tokens, "list_aliases", %{search: search})["structuredContent"]["aliases"] ==
               [
                 %{
                   "address" => disabled.address,
                   "title" => "Unrelated",
                   "notes" => "Store 100%_\\",
                   "created_at" => NaiveDateTime.to_iso8601(disabled.inserted_at) <> "Z",
                   "enabled" => false
                 }
               ]
    end

    assert tool(tokens, "list_aliases", %{search: "Store missing"})["structuredContent"][
             "aliases"
           ] == []

    for args <- [
          %{page: 0},
          %{page: 1.5},
          %{search: false},
          %{enabled: "false"},
          %{user_id: foreign.user_id}
        ] do
      assert tool(tokens, "list_aliases", args)["isError"]
    end
  end

  test "specific alias reads, edits and enables never cross accounts or change protected fields" do
    %{user: user, tokens: tokens} = connection_fixture()
    own = alias_fixture(%{user_id: user.id, title: "Before", notes: "Keep", enabled: false})
    foreign = alias_fixture(%{user_id: confirmed_user().id, title: "Foreign", enabled: false})

    for name <- ~w(get_alias edit_alias) do
      args =
        if name == "edit_alias",
          do: %{address: foreign.address, title: "Stolen"},
          else: %{address: foreign.address}

      assert tool(tokens, name, args)["isError"]
    end

    edited =
      tool(tokens, "edit_alias", %{address: own.address, title: "After"})["structuredContent"]

    assert edited == %{
             "address" => own.address,
             "title" => "After",
             "notes" => "Keep",
             "created_at" => NaiveDateTime.to_iso8601(own.inserted_at) <> "Z",
             "enabled" => false
           }

    assert tool(tokens, "edit_alias", %{address: own.address, notes: ""})["structuredContent"][
             "notes"
           ] == nil

    assert tool(tokens, "edit_alias", %{address: own.address, enabled: "true"})["isError"]
    assert tool(tokens, "edit_alias", %{address: own.address})["isError"]

    assert tool(tokens, "edit_alias", %{
             address: own.address,
             title: "Enabled title",
             notes: "New notes",
             enabled: true
           })[
             "structuredContent"
           ] == %{
             "address" => own.address,
             "title" => "Enabled title",
             "notes" => "New notes",
             "created_at" => NaiveDateTime.to_iso8601(own.inserted_at) <> "Z",
             "enabled" => true
           }

    assert tool(tokens, "get_alias", %{address: String.upcase(own.address)})["structuredContent"][
             "title"
           ] == "Enabled title"

    assert Repo.get!(Aliases.EmailAlias, foreign.id).title == "Foreign"
    Aliases.delete_email_alias(own.id)
    assert tool(tokens, "get_alias", %{address: own.address})["isError"]
  end

  test "scopes are enforced at execution without client-specific error metadata" do
    %{tokens: tokens} = connection_fixture(["aliases:read"])
    result = tool(tokens, "create_alias", %{title: "Not permitted"})
    assert result["isError"]

    assert result["structuredContent"] == %{
             "error_code" => "INSUFFICIENT_SCOPE",
             "required_scopes" => ["aliases:create", "aliases:read"]
           }

    assert result["content"] == [
             %{
               "type" => "text",
               "text" =>
                 "Required OAuth scopes: aliases:create aliases:read. Reconnect your Shroud.email account with these permissions."
             }
           ]

    refute Map.has_key?(result["_meta"] || %{}, "mcp/www_authenticate")
    domains = tool(tokens, "list_verified_domains", %{})
    assert domains["isError"]

    assert domains["content"] == [
             %{
               "type" => "text",
               "text" =>
                 "Required OAuth scopes: domains:read. Reconnect your Shroud.email account with these permissions."
             }
           ]

    assert Repo.aggregate(Aliases.EmailAlias, :count) == 0
    assert tool(tokens, "delete_alias", %{address: "anything@example.com"})["isError"]
  end

  test "create uses business limits, existing verified owned domains and rejects field injection" do
    %{user: user, tokens: tokens} = connection_fixture()

    random =
      tool(tokens, "create_alias", %{title: "Shopping", notes: "Receipts"})["structuredContent"]

    assert random["title"] == "Shopping"
    assert random["notes"] == "Receipts"
    assert random["enabled"]
    domain = custom_domain_fixture(%{user_id: user.id})
    foreign = custom_domain_fixture(%{user_id: confirmed_user().id})
    unverified = custom_domain_fixture(%{user_id: user.id, ownership_verified_at: nil})

    created =
      tool(tokens, "create_alias", %{title: "Custom", domain: domain.domain, local_part: "shop"})[
        "structuredContent"
      ]

    assert created["address"] == "shop@#{domain.domain}"

    assert tool(tokens, "list_verified_domains", %{})["structuredContent"] == %{
             "domains" => [domain.domain],
             "has_more" => false
           }

    for args <- [
          %{title: "Bad", domain: foreign.domain, local_part: "shop"},
          %{title: "Bad", domain: unverified.domain, local_part: "shop"},
          %{title: "Bad", local_part: "shop"},
          %{title: "Bad", domain: domain.domain, local_part: "shop_orders"},
          %{title: "Bad", user_id: foreign.user_id},
          %{title: "   "},
          %{title: String.duplicate("x", 256)}
        ] do
      assert tool(tokens, "create_alias", args)["isError"]
    end

    user |> Accounts.User.status_changeset(%{status: :free}) |> Repo.update!()
    for _ <- 1..3, do: tool(tokens, "create_alias", %{title: "Extra"})
    limited = tool(tokens, "create_alias", %{title: "Over limit"})
    assert limited["isError"]
    assert limited["structuredContent"] == %{"error_code" => "ALIAS_LIMIT_REACHED"}

    assert hd(limited["content"])["text"] ==
             "Your account's alias limit has been reached. Upgrade for more aliases: #{OAuth.issuer()}/settings/billing"
  end

  test "disable and enable act directly on one alias and revocation is account-scoped" do
    %{user: user, tokens: tokens, connection: connection} = connection_fixture()

    email_alias =
      alias_fixture(%{user_id: user.id, title: "Password resets", notes: "Keep these notes"})

    untouched = alias_fixture(%{user_id: user.id, title: "Other alias"})
    foreign = alias_fixture(%{user_id: confirmed_user().id, title: "Foreign", enabled: true})
    assert tool(tokens, "edit_alias", %{address: foreign.address, enabled: false})["isError"]
    assert Repo.get!(Aliases.EmailAlias, foreign.id).enabled
    %{tokens: read_only} = connection_fixture(["aliases:read"], user)

    assert tool(read_only, "edit_alias", %{address: email_alias.address, enabled: false})[
             "isError"
           ]

    assert Repo.get!(Aliases.EmailAlias, email_alias.id).enabled

    disabled =
      tool(tokens, "edit_alias", %{address: email_alias.address, enabled: false})[
        "structuredContent"
      ]

    assert disabled == %{
             "address" => email_alias.address,
             "title" => "Password resets",
             "notes" => "Keep these notes",
             "created_at" => NaiveDateTime.to_iso8601(email_alias.inserted_at) <> "Z",
             "enabled" => false
           }

    refute Repo.get!(Aliases.EmailAlias, email_alias.id).enabled
    assert Repo.get!(Aliases.EmailAlias, untouched.id).enabled

    assert tool(tokens, "edit_alias", %{address: email_alias.address, enabled: false})[
             "structuredContent"
           ] ==
             disabled

    assert tool(tokens, "edit_alias", %{address: email_alias.address, enabled: true})[
             "structuredContent"
           ][
             "enabled"
           ]

    assert Repo.get!(Aliases.EmailAlias, email_alias.id).enabled

    assert tool(tokens, "edit_alias", %{
             address: email_alias.address,
             forwarding_destination: "other@example.com"
           })[
             "isError"
           ]

    Aliases.delete_email_alias(untouched.id)
    assert tool(tokens, "edit_alias", %{address: untouched.address, enabled: false})["isError"]
    assert Repo.get!(Aliases.EmailAlias, untouched.id).enabled

    {:ok, wrong, _} =
      build_conn() |> log_in_user(confirmed_user()) |> live("/settings/security")

    assert has_element?(wrong, "#no-connections")
    render_click(wrong, "confirm_disconnect", %{"id" => to_string(connection.id)})
    refute has_element?(wrong, "#disconnect-app-dialog")
    assert has_element?(wrong, "#notification-source [data-kind=error]")
    render_click(wrong, "revoke_connection", %{"id" => to_string(connection.id)})
    assert has_element?(wrong, "#notification-source [data-kind=error]")
    assert rpc(tokens.access_token, "tools/list") |> json_response(200)

    {:ok, view, _} = build_conn() |> log_in_user(user) |> live("/settings/security")

    assert has_element?(view, "#settings-nav-security[aria-current=page]")
    assert has_element?(view, "#revoke-#{connection.id}")
    render_click(view, "revoke_connection", %{"id" => "invalid"})
    assert has_element?(view, "#notification-source [data-kind=error]")
    assert rpc(tokens.access_token, "tools/list") |> json_response(200)
    view |> element("#revoke-#{connection.id}") |> render_click()
    assert has_element?(view, "#disconnect-app-dialog[role=dialog][aria-modal=true]")
    assert has_element?(view, "#disconnect-app-dialog-title", "Disconnect Test client?")
    assert has_element?(view, "#disconnect-app-dialog [data-modal-dismiss]", "Cancel")

    assert has_element?(
             view,
             "#disconnect-app-dialog p",
             "This app will lose access immediately."
           )

    assert has_element?(view, "#disconnect-app-dialog svg")
    assert rpc(tokens.access_token, "tools/list") |> json_response(200)
    view |> element("#disconnect-app-dialog") |> render_hook("hide")
    refute has_element?(view, "#disconnect-app-dialog")
    assert has_element?(view, "#revoke-#{connection.id}")
    assert rpc(tokens.access_token, "tools/list") |> json_response(200)
    view |> element("#revoke-#{connection.id}") |> render_click()
    view |> element("#confirm-disconnect") |> render_click()
    refute has_element?(view, "#disconnect-app-dialog")
    refute has_element?(view, "#revoke-#{connection.id}")
    assert has_element?(view, "#notification-source [data-kind=info]")
    assert rpc(tokens.access_token, "tools/list") |> response(401)

    assert rpc(tokens.access_token, "tools/call", %{
             name: "edit_alias",
             arguments: %{address: email_alias.address, enabled: false}
           })
           |> response(401)

    assert Repo.get!(Aliases.EmailAlias, email_alias.id).enabled
    [remaining] = OAuth.list_connections(user)
    assert has_element?(view, "#revoke-#{remaining.id}")
    view |> element("#revoke-#{remaining.id}") |> render_click()
    view |> element("#confirm-disconnect") |> render_click()
    assert has_element?(view, "#no-connections")
    refute has_element?(view, "#connections > div")
    assert rpc(read_only.access_token, "tools/list") |> response(401)

    assert has_element?(view, "#update_password")
    assert has_element?(view, "#settings-nav-security[aria-current=page]")
  end

  test "SDK rejects invalid protocol versions, malformed requests and oversized bodies" do
    %{tokens: tokens} = connection_fixture()

    assert rpc(tokens.access_token, "tools/list", %{}, [{"mcp-protocol-version", "invalid"}])
           |> response(400)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> tokens.access_token)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    assert conn |> post(OAuth.resource(:mcp), "{") |> response(400)
    assert conn |> post(OAuth.resource(:mcp), String.duplicate("x", 65_537)) |> response(413)
  end

  test "unsupported streaming returns 405 without invalidating the authenticated session" do
    %{tokens: tokens} = connection_fixture()
    session = session_id(tokens.access_token)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> tokens.access_token)
      |> put_req_header("accept", "text/event-stream")
      |> put_req_header("mcp-session-id", session)
      |> get(OAuth.resource(:mcp))

    assert response(conn, 405)
    assert get_resp_header(conn, "allow") == ["POST, DELETE"]

    assert rpc(tokens.access_token, "tools/list", %{}, [{"mcp-session-id", session}])
           |> json_response(200)
           |> get_in(["result", "tools"])
           |> length() == 5

    assert build_conn() |> get(OAuth.resource(:mcp)) |> response(401)

    assert build_conn()
           |> put_req_header("authorization", "Bearer " <> tokens.access_token)
           |> put_req_header("origin", "https://agent.example")
           |> get(OAuth.resource(:mcp))
           |> response(405)
  end

  test "mutation tools require read permission and retain full responses" do
    %{user: user, tokens: tokens} = connection_fixture(["aliases:read", "aliases:edit"])
    email_alias = alias_fixture(%{user_id: user.id, title: "Status", notes: "Existing notes"})

    for name <- ~w(create_alias edit_alias) do
      assert OAuth.required_scopes(Tools.scope(name)) == [Tools.scope(name), "aliases:read"]
    end

    assert tool(tokens, "edit_alias", %{address: email_alias.address, enabled: true})[
             "structuredContent"
           ] ==
             %{
               "address" => email_alias.address,
               "title" => "Status",
               "notes" => "Existing notes",
               "created_at" => NaiveDateTime.to_iso8601(email_alias.inserted_at) <> "Z",
               "enabled" => true
             }

    refute tool(tokens, "get_alias", %{address: email_alias.address})["isError"]
  end

  defp tool(tokens, name, args) do
    result =
      rpc(tokens.access_token, "tools/call", %{name: name, arguments: args})
      |> json_response(200)
      |> Map.fetch!("result")

    tool = Enum.find(Tools.list(), &(&1.name == name))

    if tool do
      assert :ok = SchemaPolicy.validate(result["structuredContent"], tool.outputSchema)
    end

    if result["isError"] do
      assert is_binary(result["structuredContent"]["error_code"])
    else
      assert hd(result["content"])["text"] |> Jason.decode!() == result["structuredContent"]
    end

    result
  end

  defp rpc(token, method, params \\ %{}, headers \\ []) do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn

    modern? =
      List.keyfind(headers, "mcp-protocol-version", 0) == {"mcp-protocol-version", "2026-07-28"}

    {conn, params} =
      if modern? do
        conn = put_req_header(conn, "mcp-method", method)

        conn =
          if method == "tools/call", do: put_req_header(conn, "mcp-name", params.name), else: conn

        {conn,
         Map.put(params, :_meta, %{
           "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
           "io.modelcontextprotocol/clientCapabilities" => %{}
         })}
      else
        {conn, params}
      end

    conn =
      if token && method != "initialize" && not modern?,
        do: put_req_header(conn, "mcp-session-id", session_id(token)),
        else: conn

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    post(
      conn,
      OAuth.resource(:mcp),
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: System.unique_integer([:positive]),
        method: method,
        params: params
      })
    )
  end

  defp session_id(token) do
    conn =
      rpc(token, "initialize", %{
        protocolVersion: "2025-11-25",
        capabilities: %{},
        clientInfo: %{name: "test", version: "1"}
      })

    case get_resp_header(conn, "mcp-session-id") do
      [id] -> id
      _ -> "unauthenticated"
    end
  end

  defp hidden(html, name),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("input[name='#{name}']")
      |> LazyHTML.attribute("value")
      |> hd()
end
