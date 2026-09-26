defmodule Shroud.Accounts.PasskeysTest do
  use Shroud.DataCase

  alias Config.Reader
  alias Ecto.Adapters.SQL
  alias Shroud.Accounts.{PasskeyChallenge, PasskeyProxyResolver, Passkeys}
  import Shroud.AccountsFixtures
  import Shroud.PasskeyFixtures

  test "registration challenges are fresh and bound to a user" do
    user = user_fixture()
    other = user_fixture()
    assert {:ok, first} = Passkeys.begin_registration(user)
    assert {:ok, second} = Passkeys.begin_registration(user)

    refute first.challenge == second.challenge

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(first.token, :registration, other)

    assert {:ok, challenge} = Passkeys.consume_challenge(first.token, :registration, user)
    assert challenge.bytes == Base.url_decode64!(first.challenge, padding: false)
    assert challenge.user_verification == "required"
    assert challenge.rp_id == "localhost"

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(first.token, :registration, user)
  end

  test "authentication challenges cannot be consumed as registration" do
    assert {:ok, options} = Passkeys.begin_authentication()

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(options.token, :registration, nil)

    assert {:ok, challenge} = Passkeys.consume_challenge(options.token, :authentication, nil)
    assert challenge.user_verification == "required"
    assert challenge.origin == "http://localhost:4002"
  end

  test "expired challenge cannot be consumed" do
    assert {:ok, options} = Passkeys.begin_authentication()

    {1, _} =
      from(c in PasskeyChallenge, where: c.token == ^options.token)
      |> Repo.update_all(set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(options.token, :authentication, nil)
  end

  test "only one concurrent consumer obtains the same challenge" do
    assert {:ok, options} = Passkeys.begin_authentication()

    tasks =
      for _ <- 1..2 do
        Task.async(fn -> Passkeys.consume_challenge(options.token, :authentication, nil) end)
      end

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_challenge})) == 1
  end

  test "trusted proxy addresses normalize equivalent IPv6 spellings" do
    previous = System.get_env("PASSKEY_TRUSTED_PROXY_IPS")
    previous_proxies = Application.fetch_env(:shroud, :passkey_trusted_proxies)
    System.put_env("PASSKEY_TRUSTED_PROXY_IPS", "0:0:0:0:0:0:0:1, 192.0.2.41")

    on_exit(fn ->
      if previous,
        do: System.put_env("PASSKEY_TRUSTED_PROXY_IPS", previous),
        else: System.delete_env("PASSKEY_TRUSTED_PROXY_IPS")
    end)

    config = Reader.read!("config/runtime.exs", env: :test)

    assert [{0, 0, 0, 0, 0, 0, 0, 1}, {192, 0, 2, 41}] =
             get_in(config, [:shroud, :passkey_trusted_proxies])

    Application.put_env(
      :shroud,
      :passkey_trusted_proxies,
      get_in(config, [:shroud, :passkey_trusted_proxies])
    )

    on_exit(fn ->
      case previous_proxies do
        {:ok, proxies} -> Application.put_env(:shroud, :passkey_trusted_proxies, proxies)
        :error -> Application.delete_env(:shroud, :passkey_trusted_proxies)
      end
    end)

    conn = Plug.Test.conn(:post, "/users/passkeys/options")
    conn = %{conn | remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}}
    conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "198.51.100.2")
    assert Passkeys.request_ip(conn) == {198, 51, 100, 2}
  end

  test "a configured proxy hostname trusts only its resolved peer" do
    previous_hosts = Application.fetch_env(:shroud, :passkey_trusted_proxy_hosts)
    previous_resolved = Application.fetch_env(:shroud, :passkey_resolved_proxy_ips)
    Application.put_env(:shroud, :passkey_trusted_proxy_hosts, ["localhost"])

    on_exit(fn ->
      case previous_hosts do
        {:ok, hosts} -> Application.put_env(:shroud, :passkey_trusted_proxy_hosts, hosts)
        :error -> Application.delete_env(:shroud, :passkey_trusted_proxy_hosts)
      end

      case previous_resolved do
        {:ok, ips} -> Application.put_env(:shroud, :passkey_resolved_proxy_ips, ips)
        :error -> Application.delete_env(:shroud, :passkey_resolved_proxy_ips)
      end
    end)

    resolver = start_supervised!({PasskeyProxyResolver, name: :passkey_test_proxy_resolver})
    send(resolver, :refresh)
    :sys.get_state(resolver)

    conn = Plug.Test.conn(:post, "/users/passkeys/options")
    conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "198.51.100.2")
    assert Passkeys.request_ip(%{conn | remote_ip: {127, 0, 0, 1}}) == {198, 51, 100, 2}
    assert Passkeys.request_ip(%{conn | remote_ip: {192, 0, 2, 41}}) == {192, 0, 2, 41}

    Application.put_env(:shroud, :passkey_trusted_proxy_hosts, [])
    send(resolver, :refresh)
    :sys.get_state(resolver)
    assert Passkeys.request_ip(%{conn | remote_ip: {127, 0, 0, 1}}) == {127, 0, 0, 1}
  end

  test "proxy checks use resolved peers without looking up DNS during a request" do
    previous_hosts = Application.fetch_env(:shroud, :passkey_trusted_proxy_hosts)
    previous_resolved = Application.fetch_env(:shroud, :passkey_resolved_proxy_ips)
    Application.put_env(:shroud, :passkey_trusted_proxy_hosts, ["unresolvable.invalid"])
    Application.put_env(:shroud, :passkey_resolved_proxy_ips, [{192, 0, 2, 41}])

    on_exit(fn ->
      for {key, previous} <- [
            {:passkey_trusted_proxy_hosts, previous_hosts},
            {:passkey_resolved_proxy_ips, previous_resolved}
          ] do
        case previous do
          {:ok, value} -> Application.put_env(:shroud, key, value)
          :error -> Application.delete_env(:shroud, key)
        end
      end
    end)

    conn = Plug.Test.conn(:post, "/users/passkeys/options")
    conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "198.51.100.2")
    assert Passkeys.request_ip(%{conn | remote_ip: {192, 0, 2, 41}}) == {198, 51, 100, 2}
    assert Passkeys.request_ip(%{conn | remote_ip: {192, 0, 2, 42}}) == {192, 0, 2, 42}
  end

  test "verification-only rate-limit traffic prunes expired minute rows" do
    minute = div(System.system_time(:second), 60)

    SQL.query!(
      Repo,
      "INSERT INTO passkey_rate_limits (source, minute, attempts) VALUES ($1, $2, 1)",
      [:crypto.strong_rand_bytes(32), minute - 3]
    )

    assert Passkeys.allow_request?({198, 51, 100, 14}, :verify)

    assert Repo.aggregate(
             from(r in "passkey_rate_limits", where: r.minute < ^(minute - 2)),
             :count
           ) == 0
  end

  test "rate limits can be exercised in a controlled minute" do
    minute = div(System.system_time(:second), 60) + 10
    Application.put_env(:shroud, :passkey_rate_limit_minute, minute)
    on_exit(fn -> Application.delete_env(:shroud, :passkey_rate_limit_minute) end)

    assert Passkeys.allow_request?({192, 0, 2, 99}, :options)

    assert Repo.aggregate(from(r in "passkey_rate_limits", where: r.minute == ^minute), :count) ==
             1
  end

  test "Wax verifies an actual attestation and persists only its public credential" do
    user = user_fixture()
    {:ok, options} = Passkeys.begin_registration(user)
    {id, attestation, client_data} = registration_response(options)

    assert {:error, :invalid_registration} =
             Passkeys.register(user, options.token, attestation, client_data, "Laptop", <<1>>)

    assert Shroud.Accounts.list_passkeys(user) == []

    {:ok, options} = Passkeys.begin_registration(user)
    client_data = registration_client_data(options.challenge)

    assert {:error, :invalid_registration} =
             Passkeys.register(
               user,
               options.token,
               attestation,
               client_data,
               String.duplicate("X", 101)
             )

    assert {:error, :invalid_registration} =
             Passkeys.register(user, options.token, attestation, client_data, "Laptop")

    assert Shroud.Accounts.list_passkeys(user) == []

    {:ok, options} = Passkeys.begin_registration(user)
    client_data = registration_client_data(options.challenge)

    assert {:ok, saved} =
             Passkeys.register(user, options.token, attestation, client_data, "Laptop")

    assert saved.credential_id == id
    assert saved.user_id == user.id
    assert saved.label == "Laptop"
    assert {:error, _} = Passkeys.register(user, options.token, attestation, client_data, "Again")
    assert length(Shroud.Accounts.list_passkeys(user)) == 1
  end
end
