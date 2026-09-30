defmodule Shroud.Accounts.PasskeysTest do
  use Shroud.DataCase

  alias Ecto.Adapters.SQL
  alias Shroud.Accounts.{PasskeyChallenge, PasskeyProxyResolver, Passkeys}
  import ExUnit.CaptureLog
  import Shroud.AccountsFixtures
  import Shroud.PasskeyFixtures

  test "both ceremonies use the configured HTTPS endpoint origin and hostname" do
    config = Application.fetch_env!(:shroud, ShroudWeb.Endpoint)
    on_exit(fn -> ShroudWeb.Endpoint.config_change([{ShroudWeb.Endpoint, config}], []) end)

    ShroudWeb.Endpoint.config_change(
      [
        {ShroudWeb.Endpoint,
         Keyword.put(config, :url, host: "app.example.com", scheme: "https", port: 443)}
      ],
      []
    )

    assert Passkeys.origin_and_rp_id() == {"https://app.example.com", "app.example.com"}

    user = user_fixture()
    {:ok, registration} = Passkeys.begin_registration(user)
    {:ok, authentication} = Passkeys.begin_authentication()

    for {options, kind, owner} <- [
          {registration, :registration, user},
          {authentication, :authentication, nil}
        ] do
      assert {:ok, challenge} = Passkeys.consume_challenge(options.token, kind, owner)
      assert challenge.origin == "https://app.example.com"
      assert challenge.rp_id == "app.example.com"
    end
  end

  test "base64url decoding is shared and bounded at 24,000 encoded bytes" do
    assert Passkeys.decode_base64url("-_8") == {:ok, <<251, 255>>}

    assert Passkeys.decode_base64url(String.duplicate("A", 24_000)) ==
             {:ok, :binary.copy(<<0>>, 18_000)}

    for invalid <- [String.duplicate("A", 24_004), "!", nil, %{}] do
      assert Passkeys.decode_base64url(invalid) == :error
    end
  end

  test "resolver initializes proxy trust before returning its initial state" do
    assert {:ok, _state} =
             PasskeyProxyResolver.init(table: :passkey_boot_ips, hosts: ["localhost"])

    assert PasskeyProxyResolver.trusted?({127, 0, 0, 1}, :passkey_boot_ips)
    refute PasskeyProxyResolver.trusted?({192, 0, 2, 41}, :passkey_boot_ips)
  end

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

  test "a configured proxy hostname trusts only its resolved peer" do
    resolver =
      start_supervised!(
        {PasskeyProxyResolver,
         name: :passkey_test_proxy_resolver, table: :passkey_test_proxy_ips, hosts: ["localhost"]}
      )

    send(resolver, :refresh)
    :sys.get_state(resolver)

    conn = Plug.Test.conn(:post, "/users/passkeys/options")
    conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "198.51.100.1, 198.51.100.2")

    assert Passkeys.request_ip(%{conn | remote_ip: {127, 0, 0, 1}}, :passkey_test_proxy_ips) ==
             {198, 51, 100, 2}

    assert Passkeys.request_ip(%{conn | remote_ip: {192, 0, 2, 41}}, :passkey_test_proxy_ips) ==
             {192, 0, 2, 41}

    minute = div(System.system_time(:second), 60)
    Application.put_env(:shroud, :passkey_rate_limit_minute, minute)
    on_exit(fn -> Application.delete_env(:shroud, :passkey_rate_limit_minute) end)

    client = Passkeys.request_ip(%{conn | remote_ip: {127, 0, 0, 1}}, :passkey_test_proxy_ips)
    for _ <- 1..30, do: assert(Passkeys.allow_request?(client, :options))
    refute Passkeys.allow_request?(client, :options)

    other_conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "198.51.100.3")

    other_client =
      Passkeys.request_ip(%{other_conn | remote_ip: {127, 0, 0, 1}}, :passkey_test_proxy_ips)

    assert Passkeys.allow_request?(other_client, :options)
  end

  test "resolver snapshots are owned by their worker, not application configuration" do
    resolver =
      start_supervised!(
        {PasskeyProxyResolver,
         name: :passkey_isolated_resolver, table: :passkey_isolated_ips, hosts: ["localhost"]}
      )

    send(resolver, :refresh)
    :sys.get_state(resolver)

    assert PasskeyProxyResolver.trusted?({127, 0, 0, 1}, :passkey_isolated_ips)
    refute PasskeyProxyResolver.trusted?({192, 0, 2, 41}, :passkey_isolated_ips)
    refute PasskeyProxyResolver.trusted?({127, 0, 0, 1})
  end

  test "an unavailable configured proxy logs a warning" do
    boot_log =
      capture_log(fn ->
        start_supervised!(
          {PasskeyProxyResolver,
           name: :passkey_unavailable_resolver, table: :passkey_unavailable_ips, hosts: [""]}
        )
      end)

    refresh_log =
      capture_log(fn ->
        resolver = Process.whereis(:passkey_unavailable_resolver)
        send(resolver, :refresh)
        :sys.get_state(resolver)
      end)

    assert boot_log =~ "Passkey trusted proxy"
    assert refresh_log =~ "Passkey trusted proxy"
    refute PasskeyProxyResolver.trusted?({127, 0, 0, 1}, :passkey_unavailable_ips)
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
