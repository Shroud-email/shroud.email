defmodule Shroud.McpTest do
  use Shroud.DataCase, async: false
  import Shroud.McpFixtures
  alias Boruta.Ecto.Token
  alias Shroud.{Accounts, Mcp, Repo}
  alias Shroud.Mcp.{Clients, Connection}

  test "only the configured MCP resource, exact redirects, permissions and S256 are accepted" do
    {params, _} = authorization_params()
    assert {:ok, _} = Mcp.validate_authorization(params)

    for {key, value} <- [
          {"client_id", "unknown"},
          {"redirect_uri", "https://client.example/callback?next=evil"},
          {"resource", Mcp.issuer() <> "/api/v1"},
          {"scope", "aliases:read emails:read"},
          {"scope", "openid"},
          {"scope", ""},
          {"code_challenge_method", "plain"},
          {"response_type", "token"},
          {"request", "unsigned-request-object"},
          {"request_uri", "https://evil.example/request"}
        ] do
      assert {:error, :invalid_request} = Mcp.validate_authorization(Map.put(params, key, value))
    end

    assert {:error, :invalid_request} =
             Mcp.authorize(Shroud.AccountsFixtures.user_fixture(), params)
  end

  test "Boruta issues codes and verifies PKCE, client, redirect and expiration" do
    user = confirmed_user()
    {params, verifier} = authorization_params(["aliases:read"])
    {:ok, code} = Mcp.authorize(user, params)
    stored = Repo.get_by!(Token, value: code)
    assert stored.type == "code"
    assert stored.code_challenge_method == "S256"
    assert stored.sub == to_string(user.id)

    exchange =
      Map.merge(params, %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => verifier
      })

    for {key, value} <- [
          {"code_verifier", String.duplicate("b", 43)},
          {"client_id", client_fixture()},
          {"redirect_uri", "https://other.example/callback"},
          {"resource", "https://evil.example/mcp"}
        ] do
      assert {:error, :invalid_grant} = Mcp.exchange(Map.put(exchange, key, value))
    end

    assert {:ok, tokens} = Mcp.exchange(exchange)
    assert Repo.get_by!(Token, value: tokens.access_token).type == "access_token"
    assert :ok = Mcp.with_access(tokens.access_token, "aliases:read", fn _ -> :ok end)

    assert {:error, :insufficient_scope} =
             Mcp.with_access(tokens.access_token, "aliases:edit", fn _ ->
               flunk("unauthorized")
             end)

    assert {:error, :invalid_grant} = Mcp.exchange(exchange)

    {:ok, expired_code} = Mcp.authorize(user, params)

    Repo.get_by!(Token, value: expired_code)
    |> Ecto.Changeset.change(expires_at: 0)
    |> Repo.update!()

    assert {:error, :invalid_grant} = Mcp.exchange(Map.put(exchange, "code", expired_code))
  end

  test "Boruta rotates refresh tokens and cannot widen permissions" do
    %{tokens: first, connection: connection} = connection_fixture(["aliases:read"])

    params = %{
      "grant_type" => "refresh_token",
      "client_id" => connection.client_id,
      "resource" => Mcp.resource(),
      "refresh_token" => first.refresh_token
    }

    assert {:error, :invalid_grant} =
             Mcp.exchange(Map.put(params, "scope", "aliases:read aliases:edit"))

    assert {:error, :invalid_grant} = Mcp.exchange(Map.put(params, "client_id", client_fixture()))
    assert {:ok, second} = Mcp.exchange(params)
    refute first.refresh_token == second.refresh_token
    assert second.scope == "aliases:read"
    assert :ok = Mcp.with_access(second.access_token, "aliases:read", fn _ -> :ok end)

    assert {:ok, third} = Mcp.exchange(Map.put(params, "refresh_token", second.refresh_token))
    assert third.resource == Mcp.resource()

    for invalid <- [
          Map.put(params, "client_id", client_fixture()),
          Map.put(params, "resource", "https://evil.example/mcp"),
          Map.put(params, "refresh_token", "unknown")
        ] do
      assert {:error, :invalid_grant} = Mcp.exchange(invalid)
      assert :ok = Mcp.with_access(third.access_token, "aliases:read", fn _ -> :ok end)
    end

    assert {:error, :invalid_grant} = Mcp.exchange(params)
    assert {:error, :invalid_token} = Mcp.with_access(third.access_token, nil, fn _ -> :ok end)

    assert {:error, :invalid_grant} =
             Mcp.exchange(Map.put(params, "refresh_token", third.refresh_token))
  end

  test "refresh replay revokes only its connection regardless of requested scopes" do
    for scope <- [nil, "aliases:read aliases:edit", "unknown"] do
      %{user: user, connection: connection, tokens: first} = connection_fixture(["aliases:read"])
      %{connection: other, tokens: other_tokens} = connection_fixture(["aliases:read"], user)

      params = %{
        "grant_type" => "refresh_token",
        "client_id" => connection.client_id,
        "resource" => Mcp.resource(),
        "refresh_token" => first.refresh_token
      }

      assert {:ok, second} = Mcp.exchange(params)
      replay = if scope, do: Map.put(params, "scope", scope), else: params
      assert {:error, :invalid_grant} = Mcp.exchange(replay)
      assert Repo.get!(Connection, connection.id).revoked_at != nil
      assert Repo.get!(Connection, other.id).revoked_at == nil
      assert {:error, :invalid_token} = Mcp.with_access(second.access_token, nil, fn _ -> :ok end)
      assert :ok = Mcp.with_access(other_tokens.access_token, nil, fn _ -> :ok end)
    end
  end

  test "connections and registered clients have a 90-day refresh lifetime" do
    %{connection: connection, tokens: tokens} = connection_fixture()
    assert DateTime.diff(connection.expires_at, connection.inserted_at) == 90 * 86_400
    assert Repo.get!(Boruta.Ecto.Client, connection.client_id).refresh_token_ttl == 90 * 86_400
    assert tokens.expires_in in 3599..3600
  end

  test "narrowed refresh scopes restrict tools even though the consent granted more" do
    %{tokens: first, connection: connection} =
      connection_fixture(["aliases:read", "aliases:edit"])

    assert {:ok, second} =
             Mcp.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => connection.client_id,
               "resource" => Mcp.resource(),
               "refresh_token" => first.refresh_token,
               "scope" => "aliases:read"
             })

    assert {:error, :insufficient_scope} =
             Mcp.with_access(second.access_token, "aliases:edit", fn _ ->
               flunk("scope widened")
             end)
  end

  test "registered client lookups are read-only and other OAuth clients are rejected" do
    id = client_fixture()
    client = Clients.get_client(id)
    ref = trace_queries()
    assert Clients.get_client(id).id == client.id
    assert Clients.get_client(client.id).id == client.id
    assert_receive {^ref, "SELECT" <> _}
    refute_received {^ref, "INSERT" <> _}
    refute_received {^ref, "UPDATE" <> _}

    Repo.get!(Boruta.Ecto.Client, id)
    |> Ecto.Changeset.change(metadata: %{})
    |> Repo.update!()

    assert Clients.get_client(id) == nil
    assert Clients.metadata(id) == nil
  end

  test "invalid revocation credentials do not reach the database" do
    id = client_fixture()
    ref = trace_queries()

    for token <- [nil, "", String.duplicate("x", 1025)] do
      assert :ok = Mcp.revoke_token(token, id)
    end

    refute_received {^ref, _}
    assert :ok = Mcp.revoke_token(String.duplicate("x", 1024), id)
    assert_receive {^ref, "SELECT" <> _}
  end

  test "expired tokens, changed resources, unconfirmed accounts and removed clients reject access" do
    %{tokens: tokens} = connection_fixture()

    Repo.get_by!(Token, value: tokens.access_token)
    |> Ecto.Changeset.change(expires_at: 0)
    |> Repo.update!()

    assert {:error, :invalid_token} = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)

    %{tokens: tokens, connection: connection} = connection_fixture()

    connection
    |> Ecto.Changeset.change(resource: "https://elsewhere.example/mcp")
    |> Repo.update!()

    assert {:error, :invalid_token} = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)

    %{tokens: tokens, user: user} = connection_fixture()
    user |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()
    assert {:error, :invalid_token} = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)

    %{tokens: tokens, connection: connection} = connection_fixture()
    Repo.get!(Boruta.Ecto.Client, connection.client_id) |> Repo.delete!()
    assert {:error, :invalid_token} = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)
  end

  test "only the owning account/client can revoke and disconnected tokens cannot refresh" do
    %{user: user, tokens: tokens, connection: connection} = connection_fixture()
    refute Mcp.revoke(confirmed_user(), connection.id)
    Mcp.revoke_token(tokens.access_token, client_fixture())
    assert :ok = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)
    assert Mcp.revoke(user, connection.id)
    assert {:error, :invalid_token} = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)
    assert Mcp.list_connections(user) == []

    assert {:error, :invalid_grant} =
             Mcp.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => connection.client_id,
               "resource" => Mcp.resource(),
               "refresh_token" => tokens.refresh_token
             })
  end

  test "password reset disconnects apps" do
    %{user: user, tokens: tokens} = connection_fixture()
    password = "a different strong password"

    assert {:ok, _} =
             Accounts.reset_user_password(user, %{
               password: password,
               password_confirmation: password
             })

    assert {:error, :invalid_token} = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)
  end

  test "pruning connections retains active connections and usable refresh tokens" do
    %{connection: expired} = connection_fixture()
    %{connection: active, tokens: tokens} = connection_fixture()
    expired |> Ecto.Changeset.change(expires_at: past()) |> Repo.update!()

    forty_five_days_ago = DateTime.add(DateTime.utc_now(), -45 * 86_400)

    Repo.get_by!(Token, value: tokens.access_token)
    |> Ecto.Changeset.change(
      inserted_at: forty_five_days_ago,
      expires_at: DateTime.to_unix(forty_five_days_ago)
    )
    |> Repo.update!()

    Mcp.prune()
    refute Repo.get(Connection, expired.id)
    assert Repo.get(Connection, active.id)

    assert {:ok, _} =
             Mcp.exchange(%{
               "grant_type" => "refresh_token",
               "client_id" => active.client_id,
               "resource" => Mcp.resource(),
               "refresh_token" => tokens.refresh_token
             })
  end

  test "connection expiry also rejects fresh Boruta tokens" do
    %{tokens: tokens, connection: connection} = connection_fixture()
    connection |> Ecto.Changeset.change(expires_at: past()) |> Repo.update!()
    assert {:error, :invalid_token} = Mcp.with_access(tokens.access_token, nil, fn _ -> :ok end)
  end

  test "mutation grants require reads at authorization, refresh and access" do
    for mutation <- ~w(aliases:create aliases:edit) do
      {params, _} = authorization_params([mutation])
      assert {:error, :invalid_request} = Mcp.validate_authorization(params)

      {params, _} = authorization_params(["aliases:read", mutation])
      assert {:ok, _} = Mcp.validate_authorization(params)
      %{tokens: tokens, connection: connection} = connection_fixture(["aliases:read", mutation])

      refresh = %{
        "grant_type" => "refresh_token",
        "client_id" => connection.client_id,
        "resource" => Mcp.resource(),
        "refresh_token" => tokens.refresh_token,
        "scope" => mutation
      }

      assert {:error, :invalid_grant} = Mcp.exchange(refresh)

      assert {:ok, refreshed} =
               Mcp.exchange(Map.put(refresh, "scope", "aliases:read " <> mutation))

      assert :ok = Mcp.with_access(refreshed.access_token, "aliases:read", fn _ -> :ok end)
      assert :ok = Mcp.with_access(refreshed.access_token, mutation, fn _ -> :ok end)

      Repo.get_by!(Token, value: refreshed.access_token)
      |> Ecto.Changeset.change(scope: mutation)
      |> Repo.update!()

      assert {:error, :invalid_token} =
               Mcp.with_access(refreshed.access_token, mutation, fn _ ->
                 flunk("mutation-only")
               end)
    end
  end

  test "SDK handler timeouts retain diagnostic logging" do
    pid =
      start_supervised!(%{
        id: :mcp_timeout_handler,
        start: {GenServer, :start_link, [ShroudWeb.McpHandler, [token: "synthetic-test-token"]]}
      })

    :ok = :sys.suspend(pid)

    try do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          result =
            %{
              "jsonrpc" => "2.0",
              "id" => 1,
              "method" => "tools/call",
              "params" => %{
                "name" => "edit_alias",
                "arguments" => %{"address" => "private@example.com", "notes" => "PRIVATE_NOTES"}
              }
            }
            |> ExMCP.MessageProcessor.new()
            |> ExMCP.MessageProcessor.process(%{server: pid, handler_call_timeout: 10})

          assert result.response["error"]["data"]["type"] == "handler_timeout"
        end)

      assert log =~ "PRIVATE_NOTES"
      assert log =~ "private@example.com"
      assert log =~ "handler exited: {:timeout"
    after
      :sys.resume(pid)
      :sys.get_state(pid)
    end
  end

  test "connection request errors are retained for Sentry" do
    for path <- ["/mcp", "/oauth/token", "/oauth/authorize", "/settings/connections"] do
      event =
        struct(Sentry.Event,
          request: %Sentry.Interfaces.Request{url: Mcp.issuer() <> path <> "?code=private"}
        )

      assert Shroud.ErrorReporter.before_send(event) == event
    end
  end

  test "registered connection names are loaded in one query" do
    %{user: user, connection: connection} = connection_fixture(["aliases:read"])
    connection_fixture(["aliases:read"])

    for name <- ["Desktop agent", "Browser agent"] do
      {:ok, registration} =
        Clients.register(%{
          "client_name" => name,
          "redirect_uris" => ["https://agent.example/callback"]
        })

      {params, _verifier} = authorization_params(["aliases:read"])

      params = %{
        params
        | "client_id" => registration.client_id,
          "redirect_uri" => "https://agent.example/callback"
      }

      assert {:ok, _code} = Mcp.authorize(user, params)
    end

    ref = trace_queries()
    connections = Mcp.list_connections(user)

    assert Enum.map(connections, & &1.client_name) |> Enum.sort() ==
             ["Browser agent", "Desktop agent", "Test client"]

    assert_receive {^ref, query}
    assert query =~ "LEFT OUTER JOIN"
    refute_receive {^ref, _query}

    Repo.get!(Boruta.Ecto.Client, connection.client_id) |> Repo.delete!()

    assert Enum.map(Mcp.list_connections(user), & &1.client_name) |> Enum.sort() ==
             ["Browser agent", "Desktop agent", "Disconnected client"]
  end

  defp past, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-1)

  defp trace_queries do
    ref = make_ref()
    owner = self()

    :ok =
      :telemetry.attach(
        ref,
        [:shroud, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == owner, do: send(owner, {ref, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end
end
