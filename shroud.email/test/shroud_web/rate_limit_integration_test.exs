defmodule ShroudWeb.RateLimitIntegrationTest do
  use ShroudWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Shroud.AccountsFixtures
  alias Shroud.{Accounts, RateLimit, Repo}
  alias Shroud.Accounts.{TOTP, User}
  alias ShroudWeb.Plugs.ClientIP

  setup do
    # Freeze refreshes while exercising controlled snapshots. Requests must
    # still complete: they may not call the suspended cache process or DNS.
    :sys.suspend(ShroudWeb.TrustedProxies)
    [snapshot] = :ets.lookup(ShroudWeb.TrustedProxies, :snapshot)
    cache_proxy_addresses([])

    on_exit(fn ->
      :sys.replace_state(ShroudWeb.TrustedProxies, fn state ->
        :ets.insert(ShroudWeb.TrustedProxies, snapshot)
        state
      end)

      :sys.resume(ShroudWeb.TrustedProxies)
    end)

    :ok
  end

  test "the actual endpoint rejects dynamic requests, but not exact exemptions", %{conn: conn} do
    seed(:http, {:ip, conn.remote_ip}, 600)
    assert get(conn, "/users/log_in").status == 429
    assert get(conn, "/unknown/path").status == 429
    assert get(conn, "/_health/extra").status == 429
    assert get(conn, "/_health").status == 200
    assert post(conn, "/api/webhooks/paddle", %{}).status == 400
    assert post(conn, "/api/webhooks/paddle/extra", %{}).status == 429
  end

  test "WebSocket upgrades are limited before a LiveView joins", %{conn: conn} do
    conn = get(conn, "/users/log_in")
    csrf = get_session(conn, :_csrf_token)
    seed(:http, {:ip, conn.remote_ip}, 600)

    response =
      conn
      |> recycle()
      |> put_req_header("connection", "upgrade")
      |> put_req_header("upgrade", "websocket")
      |> put_req_header("sec-websocket-version", "13")
      |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
      |> get("/live/websocket?vsn=2.0.0&_csrf_token=#{URI.encode_www_form(csrf)}")

    assert response.status == 429
    assert [_] = get_resp_header(response, "retry-after")
  end

  test "MCP and OAuth routes inherit the global IP limit", %{conn: conn} do
    seed(:http, {:ip, conn.remote_ip}, 600)

    for {method, path} <- [
          {:get, "/.well-known/oauth-authorization-server"},
          {:get, "/.well-known/oauth-protected-resource/mcp"},
          {:get, "/oauth/authorize"},
          {:post, "/oauth/authorize"},
          {:post, "/oauth/token"},
          {:post, "/oauth/revoke"},
          {:post, "/mcp"},
          {:options, "/mcp"}
        ] do
      response = Phoenix.ConnTest.dispatch(conn, @endpoint, method, path, %{})
      assert response.status == 429
      assert [_] = get_resp_header(response, "retry-after")
    end
  end

  test "OAuth token and revocation routes share an IP quota including encoded paths", %{
    conn: conn
  } do
    seed(:api, {:ip, conn.remote_ip}, 119)
    assert post(conn, "/oauth/token", %{}).status == 400

    for path <- ["/oauth/token", "/oauth/revoke", "/oauth/%74oken", "/oauth/%72evoke"] do
      response = post(conn, path, %{client_id: "different-client", token: "different-token"})
      assert response.status == 429
      assert [_] = get_resp_header(response, "retry-after")
    end

    assert post(build_conn(), "/oauth/token", %{}).status == 400
  end

  test "global MCP rejection preserves CORS for any origin on the MCP host and path", %{
    conn: conn
  } do
    seed(:http, {:ip, conn.remote_ip}, 600)

    for method <- [:post, :options], path <- ["/mcp", "/m%63p"] do
      response =
        conn
        |> put_req_header("origin", "https://agent.example")
        |> Phoenix.ConnTest.dispatch(@endpoint, method, Shroud.Mcp.issuer() <> path, %{})

      assert response.status == 429
      assert get_resp_header(response, "access-control-allow-origin") == ["https://agent.example"]
      assert get_resp_header(response, "access-control-expose-headers") |> hd() =~ "Retry-After"
      assert [_] = get_resp_header(response, "retry-after")
    end

    for {origin, url} <- [
          {"https://chatgpt.com", "https://evil.example/mcp"},
          {"https://chatgpt.com", Shroud.Mcp.issuer() <> "/oauth/token"}
        ] do
      rejected = conn |> put_req_header("origin", origin) |> post(url, %{})
      assert rejected.status == 429
      assert get_resp_header(rejected, "access-control-allow-origin") == []
    end
  end

  test "MCP shares the REST account quota across connections and IPs", %{conn: conn} do
    Shroud.McpFixtures.configure_clients()
    %{user: user, tokens: tokens} = Shroud.McpFixtures.connection_fixture()
    %{tokens: second} = Shroud.McpFixtures.connection_fixture(["aliases:read"], user)
    %{tokens: other} = Shroud.McpFixtures.connection_fixture(["aliases:read"])
    seed(:api, {:account, user.id}, 119)

    assert mcp(conn, tokens.access_token).status == 200

    rest_token = user |> Accounts.generate_user_session_token() |> Base.encode64()

    assert conn
           |> put_req_header("authorization", "Bearer #{rest_token}")
           |> get("/api/v1/aliases")
           |> json_response(429)

    response = mcp(build_conn(), second.access_token)
    assert response.status == 429
    assert [_] = get_resp_header(response, "retry-after")
    assert mcp(build_conn(), "invalid").status == 401
    assert mcp(build_conn(), other.access_token).status == 200
  end

  test "exhausted MCP quota stops mutations while preserving browser CORS", %{conn: conn} do
    Shroud.McpFixtures.configure_clients()
    %{user: user, tokens: tokens} = Shroud.McpFixtures.connection_fixture()
    email_alias = Shroud.AliasesFixtures.alias_fixture(%{user_id: user.id, enabled: true})
    [session] = mcp(conn, tokens.access_token) |> get_resp_header("mcp-session-id")
    seed(:api, {:account, user.id}, 120)

    conn =
      conn
      |> put_req_header("origin", "https://chatgpt.com")
      |> put_req_header("mcp-session-id", session)

    response =
      mcp(conn, tokens.access_token, "tools/call", %{
        name: "edit_alias",
        arguments: %{address: email_alias.address, enabled: false}
      })

    assert response.status == 429
    assert get_resp_header(response, "access-control-allow-origin") == ["https://chatgpt.com"]
    assert get_resp_header(response, "access-control-expose-headers") |> hd() =~ "Retry-After"
    assert Repo.get!(Shroud.Aliases.EmailAlias, email_alias.id).enabled
    assert options(conn, Shroud.Mcp.resource()).status == 204
  end

  test "encoded routes cannot bypass their narrower policies", %{conn: conn} do
    seed(:sign_in, {:ip, conn.remote_ip}, 10)

    assert post(conn, "/users/%6Cog_in", %{user: %{email: "absent", password: "bad"}}).status ==
             429

    seed(:account_email, {:ip, conn.remote_ip}, 5)
    assert post(conn, "/users/reset_%70assword", %{}).status == 429

    user = user_fixture() |> User.confirm_changeset() |> Repo.update!()
    token = user |> Accounts.generate_user_session_token() |> Base.encode64()
    seed(:api, {:account, user.id}, 120)

    assert %{"error" => _} =
             conn
             |> put_req_header("authorization", "Bearer #{token}")
             |> get("/api/v1/%61liases")
             |> json_response(429)
  end

  test "sign-in interfaces share one IP policy, with browser and JSON responses", %{conn: conn} do
    seed(:sign_in, {:ip, conn.remote_ip}, 9)

    assert post(conn, "/api/v1/token", %{email: "absent@example.com", password: "wrong"}).status ==
             403

    browser =
      post(conn, "/users/log_in", %{user: %{email: "absent@example.com", password: "wrong"}})

    assert browser.status == 429
    assert [seconds] = get_resp_header(browser, "retry-after")
    assert String.to_integer(seconds) > 0
    assert post(conn, "/users/passkeys", %{}).status == 429
    assert %{"error" => _} = conn |> post("/api/v1/token", %{}) |> json_response(429)
    assert get(build_conn(), "/users/log_in").status == 200
  end

  test "account-email, credential, image and billing policies are mounted", %{conn: conn} do
    user = user_fixture() |> User.confirm_changeset() |> Repo.update!()
    conn = log_in_user(conn, user)

    for {policy, actor, method, path} <- [
          {:account_email, {:ip, conn.remote_ip}, :post, "/users/register"},
          {:account_email, {:ip, conn.remote_ip}, :post, "/users/reset_password"},
          {:account_email, {:ip, conn.remote_ip}, :post, "/users/confirm"},
          {:account_email, {:ip, conn.remote_ip}, :post, "/users/confirm/arbitrary"},
          {:credentials, {:ip, conn.remote_ip}, :put, "/users/reset_password/arbitrary"},
          {:credentials, {:account, user.id}, :put, "/settings/password"},
          {:image_proxy, {:ip, conn.remote_ip}, :get, "/proxy?url=https://example.com/image.png"},
          {:billing, {:account, user.id}, :post, "/checkout/paddle"},
          {:billing, {:account, user.id}, :get, "/checkout/billing"}
        ] do
      {_scale, limit} = RateLimit.policy(policy)
      seed(policy, actor, limit)
      assert Phoenix.ConnTest.dispatch(conn, @endpoint, method, path, %{}).status == 429
    end
  end

  test "method override cannot bypass the password policy", %{conn: conn} do
    seed(:credentials, {:ip, conn.remote_ip}, 5)
    assert post(conn, "/users/reset_password/another-token", %{_method: "put"}).status == 429
  end

  test "API account quota survives token rotation and resource changes", %{conn: conn} do
    user = user_fixture() |> User.confirm_changeset() |> Repo.update!()
    seed(:api, {:account, user.id}, 120)

    for path <- ["/api/v1/aliases", "/api/v1/aliases/changed", "/api/v1/domains"] do
      token = user |> Accounts.generate_user_session_token() |> Base.encode64()
      response = conn |> put_req_header("authorization", "Bearer #{token}") |> get(path)
      assert %{"error" => _} = json_response(response, 429)
    end

    other = user_fixture() |> User.confirm_changeset() |> Repo.update!()
    token = other |> Accounts.generate_user_session_token() |> Base.encode64()

    assert conn
           |> put_req_header("authorization", "Bearer #{token}")
           |> get("/api/v1/domains")
           |> json_response(200)
  end

  test "second-factor account quota blocks backup-code consumption", %{conn: conn} do
    user = user_fixture()
    [backup | _] = TOTP.enable_totp!(user, TOTP.create_secret())
    seed(:second_factor, {:account, user.id}, 5)

    response =
      conn
      |> init_test_session(%{totp_pending_user_params: %{"email" => user.email}})
      |> post("/users/to%74p", %{verification_code: backup})

    assert response.status == 429
    assert backup in Repo.reload!(user).totp_backup_codes
    refute get_session(response, :user_token)

    response =
      post(build_conn(), "/api/v1/token", %{
        email: user.email,
        password: "wrong-password",
        totp: 123_456
      })

    assert response.status == 403

    response =
      post(build_conn(), "/api/v1/token", %{
        email: user.email,
        password: valid_user_password(),
        totp: 123_456
      })

    assert response.status == 429
  end

  test "settings email and security events stop before mutation and survive reconnection", %{
    conn: conn
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    seed(:account_email, {:account, user.id}, 5)
    {:ok, view, _} = live(conn, "/settings/account")

    render_submit(view, "update_email", %{
      current_password: valid_user_password(),
      user: %{email: "new@example.com"}
    })

    assert has_element?(view, "#notification-source [data-kind=error]", "Too many requests")
    refute_receive {:email, _}
    assert Repo.reload!(user).email == user.email

    seed({:security, :second_factor}, {:account, user.id}, 5)
    {:ok, security, _} = live(conn, "/settings/security")
    render_click(security, "generate_totp_secret")
    assert has_element?(security, "#notification-source [data-kind=error]", "Too many requests")
    refute Repo.reload!(user).totp_enabled

    # Display-only events still work; the socket remains connected.
    render_hook(security, "passkey_supported", %{supported: false})
    assert has_element?(security, "#update_password")
  end

  test "LiveView mounts use their own allowance rather than counting HTTP twice", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    seed(:http, {:ip, conn.remote_ip}, 599)
    {:ok, view, _} = live(conn, "/settings/security")
    assert has_element?(view, "#update_password")

    seed(:http, {:ip, conn.remote_ip}, 0)
    seed(:live_mount, {:ip, conn.remote_ip}, 600)
    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, "/settings/security")
  end

  test "ordinary events remain usable beyond the former cap without spending security quota", %{
    conn: conn
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _} = live(conn, "/settings/security")
    view |> element("#add-passkey-button") |> render_click()

    for _ <- 1..120, do: render_hook(view, "passkey_supported", %{supported: false})
    assert has_element?(view, "#passkey-confirm[disabled]")
    render_hook(view, "passkey_supported", %{supported: true})
    assert has_element?(view, "#passkey-confirm:not([disabled])")

    render_click(view, "generate_totp_secret")
    assert has_element?(view, "#totp-qr-code")

    seed({:security, :second_factor}, {:account, user.id}, 5)
    {:ok, view, _} = live(conn, "/settings/security")
    render_click(view, "generate_totp_secret")
    assert has_element?(view, "#notification-source [data-kind=error]", "Too many requests")
    refute has_element?(view, "#totp-qr-code")
  end

  test "public passkey challenge quota uses the connection peer", %{conn: conn} do
    conn = get(conn, "/users/log_in")

    {:ok, view, _} =
      live_isolated(recycle(conn), ShroudWeb.PasskeyLoginLive,
        session: %{"csrf" => get_session(conn, :_csrf_token)}
      )

    seed(:passkey_challenge, {:ip, conn.remote_ip}, 10)
    render_hook(view, "passkey_options")
    assert_reply(view, %{error: message, retry_after: seconds})
    assert message =~ "Too many requests"
    assert seconds > 0
    assert has_element?(view, "#passkey-login-status", "Too many requests")
  end

  test "trusted proxy clients are independent and untrusted forged headers are ignored", %{
    conn: conn
  } do
    proxy = {127, 0, 0, 1}
    cache_proxy_addresses([proxy])
    seed(:http, {:ip, {192, 0, 2, 10}}, 600)

    proxy_conn = %{conn | remote_ip: proxy}

    assert proxy_conn
           |> put_req_header("x-forwarded-for", "198.51.100.99, 192.0.2.10")
           |> get("/users/log_in")
           |> Map.fetch!(:status) == 429

    assert proxy_conn
           |> put_req_header("x-forwarded-for", "192.0.2.11")
           |> get("/users/log_in")
           |> Map.fetch!(:status) == 200

    seed(:http, {:ip, conn.remote_ip}, 600)

    assert conn
           |> put_req_header("x-forwarded-for", "192.0.2.11")
           |> get("/users/log_in")
           |> Map.fetch!(:status) == 429
  end

  test "requests ignore stale or missing proxy snapshots", %{conn: conn} do
    peer = {127, 0, 0, 1}
    headers = [{"x-forwarded-for", "192.0.2.10"}]
    cache_proxy_addresses([peer])
    assert ClientIP.resolve(peer, headers) == {192, 0, 2, 10}
    assert ClientIP.resolve({127, 0, 0, 2}, headers) == {127, 0, 0, 2}

    seed(:http, {:ip, {192, 0, 2, 10}}, 600)

    assert %{conn | remote_ip: peer}
           |> put_req_header("x-forwarded-for", "192.0.2.10")
           |> get("/users/log_in")
           |> Map.fetch!(:status) == 429

    cache_proxy_addresses([peer], System.monotonic_time(:millisecond) - 1)
    assert ClientIP.resolve(peer, headers) == peer

    seed(:http, {:ip, peer}, 600)

    assert %{conn | remote_ip: peer}
           |> put_req_header("x-forwarded-for", "192.0.2.11")
           |> get("/users/log_in")
           |> Map.fetch!(:status) == 429

    cache_proxy_addresses([])
    assert ClientIP.resolve(peer, headers) == peer
  end

  test "proxy parsing rejects malformed chains, duplicate headers and implicit private trust" do
    proxy = {127, 0, 0, 1}
    cache_proxy_addresses([proxy])

    assert ClientIP.resolve(proxy, [{"x-forwarded-for", "198.51.100.9, 10.0.0.3, 127.0.0.1"}]) ==
             {10, 0, 0, 3}

    assert ClientIP.resolve({127, 0, 0, 2}, [{"x-forwarded-for", "192.0.2.1"}]) == {127, 0, 0, 2}
    assert ClientIP.resolve(proxy, [{"x-forwarded-for", "bad, 192.0.2.1"}]) == proxy

    assert ClientIP.resolve(proxy, [
             {"x-forwarded-for", "192.0.2.1"},
             {"x-forwarded-for", "192.0.2.2"}
           ]) == proxy

    assert ClientIP.resolve(proxy, [{"x-forwarded-for", "::ffff:192.0.2.1"}]) == {192, 0, 2, 1}

    assert ClientIP.resolve(proxy, [{"x-forwarded-for", "2001:db8::a"}]) ==
             {8193, 3512, 0, 0, 0, 0, 0, 10}
  end

  defp cache_proxy_addresses(
         addresses,
         expires_at \\ System.monotonic_time(:millisecond) + 60_000
       ) do
    :sys.replace_state(ShroudWeb.TrustedProxies, fn state ->
      :ets.insert(ShroudWeb.TrustedProxies, {:snapshot, expires_at, addresses})
      state
    end)
  end

  defp mcp(
         conn,
         token,
         method \\ "initialize",
         params \\ %{
           protocolVersion: "2025-11-25",
           capabilities: %{},
           clientInfo: %{name: "rate-limit-test", version: "1"}
         }
       ) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post(
      Shroud.Mcp.resource(),
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: System.unique_integer([:positive]),
        method: method,
        params: params
      })
    )
  end

  defp seed(policy, actor, count) do
    {scale, _limit} = RateLimit.policy(policy)
    window = div(System.system_time(:millisecond), scale)

    # Seed current and next windows so real-route tests cannot flake at a
    # wall-clock boundary. Exercise the actual atomic backend, not a mock plug.
    # This helper alone depends on Hammer 7.5's FixWindow ETS/atomics layout:
    # set/3 cannot target a future window. Recheck the layout on Hammer upgrades.
    # Route rejection assertions ensure an incompatible seed cannot pass silently.
    for w <- [window, window + 1] do
      key = {{policy, actor}, w}
      counter = :atomics.new(2, signed: false)
      :atomics.put(counter, 1, count)
      :atomics.put(counter, 2, (w + 1) * scale)
      :ets.insert(RateLimit, {key, counter})
      on_exit(fn -> :ets.delete(RateLimit, key) end)
    end
  end
end
