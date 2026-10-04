defmodule Shroud.OAuthConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Mox
  import Shroud.OAuthFixtures
  alias Boruta.Ecto.{AccessTokens, Token}
  alias Ecto.Adapters.SQL.Sandbox
  alias Shroud.{OAuth, Repo}

  setup do
    original = Application.fetch_env!(:boruta, Boruta.Oauth)
    user = Sandbox.unboxed_run(Repo, &confirmed_user/0)

    on_exit(fn ->
      Application.put_env(:boruta, Boruta.Oauth, original)

      Sandbox.unboxed_run(Repo, fn ->
        client_ids =
          Repo.all(from t in Token, where: t.sub == ^to_string(user.id), select: t.client_id)

        Repo.delete_all(from t in Token, where: t.sub == ^to_string(user.id))
        Repo.delete!(user)

        Repo.delete_all(from c in Boruta.Ecto.Client, where: c.id in ^client_ids)
      end)
    end)

    %{user: user, config: original, supervisor: start_supervised!(Task.Supervisor)}
  end

  for grant <- ["authorization_code", "refresh_token"] do
    @grant grant
    test "connection lock permits only one concurrent #{@grant} exchange", context do
      grant = @grant
      {params, connection} = Sandbox.unboxed_run(Repo, fn -> credential(context.user, grant) end)
      before = Sandbox.unboxed_run(Repo, fn -> token_count(context.user) end)
      parent = self()
      stub_with(Shroud.MockBorutaAccessTokens, AccessTokens)

      stub(Shroud.MockBorutaAccessTokens, :create, fn attrs, opts ->
        send(parent, {:validated, self()})
        receive do: (:create -> AccessTokens.create(attrs, opts))
      end)

      config =
        Keyword.update!(
          context.config,
          :contexts,
          &Keyword.put(&1, :access_tokens, Shroud.MockBorutaAccessTokens)
        )

      Application.put_env(:boruta, Boruta.Oauth, config)

      {first_task, first_backend} = start_exchange(context, params)
      assert_receive {:validated, first}, 2_000
      {second_task, second_backend} = start_exchange(context, params)

      try do
        Sandbox.unboxed_run(Repo, fn ->
          await_database_lock(
            first_backend,
            second_backend,
            System.monotonic_time(:millisecond) + 2_000
          )
        end)

        send(first, :create)
        assert {:ok, winner} = Task.await(first_task, 5_000)
        assert {:error, :invalid_grant} = Task.await(second_task, 5_000)
        refute_receive {:validated, _}

        Sandbox.unboxed_run(Repo, fn ->
          assert token_count(context.user) == before + 1

          assert Repo.aggregate(
                   from(l in "oauth_connection_tokens", where: l.connection_id == ^connection.id),
                   :count
                 ) == before + 1

          if grant == "refresh_token" do
            assert Repo.get!(OAuth.Connection, connection.id).revoked_at != nil

            assert {:error, :invalid_token} =
                     OAuth.with_access(winner.access_token, OAuth.resource(:mcp), nil, fn _ ->
                       :ok
                     end)

            assert {:error, :invalid_grant} =
                     OAuth.exchange(Map.put(params, "refresh_token", winner.refresh_token))
          else
            assert :ok =
                     OAuth.with_access(
                       winner.access_token,
                       OAuth.resource(:mcp),
                       "aliases:read",
                       fn _ -> :ok end
                     )
          end

          assert {:error, :invalid_grant} = OAuth.exchange(params)
        end)
      after
        send(first_task.pid, :create)
        send(second_task.pid, :create)
      end
    end
  end

  test "built-in cache bypass does not retain values" do
    assert Boruta.Config.cache_backend() == Boruta.Cache
    assert :ok = Boruta.Cache.put(:mcp_cache_test, "not stored")
    assert {:ok, nil} = Boruta.Cache.get(:mcp_cache_test)
  end

  test "failed refresh rolls back the successor and predecessor consumption", context do
    {params, _connection} =
      Sandbox.unboxed_run(Repo, fn -> credential(context.user, "refresh_token") end)

    before = Sandbox.unboxed_run(Repo, fn -> token_count(context.user) end)
    stub_with(Shroud.MockBorutaAccessTokens, AccessTokens)

    stub(Shroud.MockBorutaAccessTokens, :revoke_refresh_token, fn token ->
      assert {:ok, _} = AccessTokens.revoke_refresh_token(token)
      {:error, "injected failure after revocation"}
    end)

    config =
      Keyword.update!(
        context.config,
        :contexts,
        &Keyword.put(&1, :access_tokens, Shroud.MockBorutaAccessTokens)
      )

    Application.put_env(:boruta, Boruta.Oauth, config)

    Sandbox.unboxed_run(Repo, fn ->
      assert {:error, :invalid_grant} = OAuth.exchange(params)
      assert token_count(context.user) == before
      predecessor = Repo.get_by!(Token, refresh_token: params["refresh_token"])
      assert predecessor.refresh_token_revoked_at == nil
      Application.put_env(:boruta, Boruta.Oauth, context.config)
      assert {:ok, _} = OAuth.exchange(params)
    end)
  end

  test "an authorization code without a connection cannot exchange", context do
    Sandbox.unboxed_run(Repo, fn ->
      {params, connection} = credential(context.user, "authorization_code")
      Repo.delete!(connection)
      assert Repo.get_by(Token, value: params["code"])
      assert {:error, :invalid_grant} = OAuth.exchange(params)
      assert token_count(context.user) == 0
    end)
  end

  defp credential(user, "authorization_code") do
    {params, verifier} = authorization_params(["aliases:read"])
    {:ok, code} = OAuth.authorize(user, params)

    params =
      Map.merge(params, %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => verifier
      })

    {params, hd(OAuth.list_connections(user))}
  end

  defp credential(user, "refresh_token") do
    %{tokens: tokens, connection: connection} = connection_fixture(["aliases:read"], user)

    {%{
       "grant_type" => "refresh_token",
       "client_id" => connection.client_id,
       "resource" => OAuth.resource(:mcp),
       "refresh_token" => tokens.refresh_token
     }, connection}
  end

  defp start_exchange(context, params) do
    parent = self()

    task =
      Task.Supervisor.async_nolink(context.supervisor, fn ->
        receive do
          :exchange ->
            Sandbox.unboxed_run(Repo, fn ->
              [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
              send(parent, {:started, self(), backend})
              OAuth.exchange(params)
            end)
        end
      end)

    allow(Shroud.MockBorutaAccessTokens, parent, task.pid)
    send(task.pid, :exchange)
    pid = task.pid
    assert_receive {:started, ^pid, backend}, 2_000
    {task, backend}
  end

  defp await_database_lock(first, second, deadline) do
    [[blocked]] = Repo.query!("SELECT $1 = ANY(pg_blocking_pids($2))", [first, second]).rows

    unless blocked do
      assert System.monotonic_time(:millisecond) < deadline,
             "second exchange did not wait for the connection lock"

      await_database_lock(first, second, deadline)
    end
  end

  defp token_count(user),
    do:
      Repo.aggregate(
        from(t in Token, where: t.sub == ^to_string(user.id) and t.type == "access_token"),
        :count
      )
end
