defmodule ShroudWeb.McpRegistrationTest do
  use ShroudWeb.ConnCase, async: false
  import Shroud.McpFixtures
  import Phoenix.LiveViewTest
  alias Shroud.{Mcp, Repo}

  test "an unknown client can register, obtain consent, call tools, refresh and revoke" do
    for callback <- ["https://agent.example/callback", "http://127.0.0.1:49123/callback"] do
      registration =
        register(%{"client_name" => "Independent agent", "redirect_uris" => [callback]})

      assert registration["token_endpoint_auth_method"] == "none"
      refute Map.has_key?(registration, "client_secret")
      assert Repo.get!(Boruta.Ecto.Client, registration["client_id"]).metadata["mcp_dynamic"]

      user = confirmed_user()
      {params, verifier} = authorization_params(["aliases:read"])
      params = %{params | "client_id" => registration["client_id"], "redirect_uri" => callback}

      assert {:error, :invalid_request} =
               Mcp.validate_authorization(%{params | "redirect_uri" => callback <> "/other"})

      assert {:error, :invalid_request} =
               Mcp.validate_authorization(Map.delete(params, "code_challenge"))

      html =
        build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

      document = Floki.parse_document!(html)
      assert Floki.text(Floki.find(document, "#unverified-client")) =~ callback
      assert Floki.find(document, "header a[href='/settings/connections']") != []

      approval =
        document |> Floki.find("input[name=approval]") |> Floki.attribute("value") |> hd()

      response =
        build_conn()
        |> log_in_user(user)
        |> post("/oauth/authorize", %{approval: approval, decision: "allow"})
        |> redirected_to()
        |> URI.parse()

      code = URI.decode_query(response.query)["code"]

      exchange =
        Map.merge(params, %{
          "grant_type" => "authorization_code",
          "code" => code,
          "code_verifier" => verifier
        })

      assert build_conn()
             |> post("/oauth/token", %{exchange | "code_verifier" => String.duplicate("b", 43)})
             |> json_response(400)

      tokens = build_conn() |> post("/oauth/token", exchange) |> json_response(200)
      assert [%{client_name: "Independent agent"}] = Mcp.list_connections(user)
      {:ok, view, _html} = build_conn() |> log_in_user(user) |> live("/settings/connections")
      assert has_element?(view, "#connections h2", "Independent agent")

      initialized =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> tokens["access_token"])
        |> put_req_header("content-type", "application/json")
        |> post(
          Mcp.resource(),
          Jason.encode!(%{
            jsonrpc: "2.0",
            id: 0,
            method: "initialize",
            params: %{
              protocolVersion: "2025-11-25",
              capabilities: %{},
              clientInfo: %{name: "Independent agent", version: "1"}
            }
          })
        )

      assert json_response(initialized, 200)["result"]["protocolVersion"] == "2025-11-25"
      [session] = get_resp_header(initialized, "mcp-session-id")

      result =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> tokens["access_token"])
        |> put_req_header("mcp-session-id", session)
        |> put_req_header("content-type", "application/json")
        |> post(
          Mcp.resource(),
          Jason.encode!(%{
            jsonrpc: "2.0",
            id: 1,
            method: "tools/call",
            params: %{name: "list_aliases", arguments: %{}}
          })
        )
        |> json_response(200)

      assert result["result"]["structuredContent"] == %{
               "aliases" => [],
               "has_more" => false,
               "next_cursor" => nil
             }

      refresh = %{
        "client_id" => registration["client_id"],
        "resource" => Mcp.resource(),
        "grant_type" => "refresh_token",
        "refresh_token" => tokens["refresh_token"]
      }

      assert build_conn()
             |> post("/oauth/token", %{refresh | "client_id" => client_fixture()})
             |> json_response(400)

      rotated = build_conn() |> post("/oauth/token", refresh) |> json_response(200)
      refute rotated["refresh_token"] == tokens["refresh_token"]

      assert build_conn()
             |> post("/oauth/revoke", %{
               client_id: registration["client_id"],
               token: rotated["access_token"]
             })
             |> response(200)

      assert {:error, :invalid_token} =
               Mcp.with_access(rotated["access_token"], nil, fn _ -> :ok end)

      assert build_conn()
             |> post("/oauth/token", %{refresh | "refresh_token" => rotated["refresh_token"]})
             |> json_response(400)
    end
  end

  test "registration validates callbacks and public-client metadata without accepting supplied policy" do
    for callback <- [
          "http://agent.example/callback",
          "http://localhost.evil.example/callback",
          "http://user@localhost/callback",
          "https://agent.example/callback#fragment",
          "https://agent.example/call back",
          "https://agent.example:bad/callback",
          "https://agent.example:99999/callback",
          "javascript:alert(1)",
          nil
        ] do
      response =
        build_conn()
        |> post("/oauth/register", %{redirect_uris: [callback]})
        |> json_response(400)

      assert response["error"] == "invalid_redirect_uri"
    end

    for attrs <- [
          %{client_name: ""},
          %{client_name: 42},
          %{grant_types: ["client_credentials"]},
          %{response_types: ["token"]},
          %{token_endpoint_auth_method: "client_secret_post"}
        ] do
      response =
        build_conn()
        |> post(
          "/oauth/register",
          Map.put(attrs, :redirect_uris, ["https://agent.example/callback"])
        )
        |> json_response(400)

      assert response["error"] == "invalid_client_metadata"
    end

    assert Repo.aggregate(Boruta.Ecto.Client, :count) == 0

    registration =
      register(%{
        "redirect_uris" => ["http://localhost:4567/callback", "http://[::1]:7654/callback"],
        "client_id" => "test-client",
        "pkce" => false,
        "metadata" => %{"mcp_dynamic" => false}
      })

    refute registration["client_id"] == "test-client"
    assert Mcp.Clients.get_client(registration["client_id"]).pkce
    assert Mcp.Clients.metadata(registration["client_id"])["mcp_dynamic"]

    # An arbitrary Boruta client is not an MCP registration.
    client =
      Repo.get!(Boruta.Ecto.Client, registration["client_id"])
      |> Ecto.Changeset.change(metadata: %{})
      |> Repo.update!()

    assert Mcp.Clients.metadata(client.id) == nil
    assert Mcp.Clients.get_client(client.id) == nil
  end

  test "browser clients can discover, register and exchange across origins without cookies" do
    for path <- [
          "/.well-known/oauth-authorization-server",
          "/.well-known/oauth-protected-resource/mcp",
          "/oauth/register",
          "/oauth/token",
          "/oauth/revoke"
        ] do
      conn =
        build_conn()
        |> put_req_header("origin", "https://agent.example")
        |> options(Mcp.issuer() <> path)

      assert response(conn, 204) == ""
      assert get_resp_header(conn, "access-control-allow-origin") == ["https://agent.example"]
      assert get_resp_header(conn, "access-control-allow-credentials") == []
      assert get_resp_header(conn, "access-control-allow-headers") == ["Content-Type, Accept"]
    end

    conn =
      build_conn()
      |> put_req_header("origin", "https://agent.example")
      |> post(Mcp.issuer() <> "/oauth/register", %{
        redirect_uris: ["https://agent.example/callback"]
      })

    assert json_response(conn, 201)["client_id"]
    assert get_resp_header(conn, "access-control-allow-origin") == ["https://agent.example"]
  end

  test "registration limits database growth per source IP" do
    conn = build_conn()

    for _ <- 1..10 do
      assert conn
             |> post("/oauth/register", %{redirect_uris: ["https://agent.example/callback"]})
             |> json_response(201)
    end

    denied = conn |> post("/oauth/register", %{redirect_uris: ["https://agent.example/callback"]})
    assert response(denied, 429)
    assert get_resp_header(denied, "retry-after") != []
    assert Repo.aggregate(Boruta.Ecto.Client, :count) == 10
  end

  defp register(attrs) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/oauth/register", Jason.encode!(attrs))
    |> json_response(201)
  end
end
