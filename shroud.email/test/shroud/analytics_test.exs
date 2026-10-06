defmodule Shroud.AnalyticsTest do
  use Shroud.DataCase, async: false

  alias Shroud.{Accounts, Analytics, Repo}
  import Shroud.AccountsFixtures

  setup do
    previous = Application.get_env(:shroud, :openpanel)
    bypass = Bypass.open()

    Application.put_env(:shroud, :openpanel,
      enabled: true,
      client_id: "test-client",
      client_secret: "test-secret",
      api_url: "http://localhost:#{bypass.port}/api"
    )

    on_exit(fn ->
      for task <- Task.Supervisor.children(Shroud.Analytics.Tasks) do
        ref = Process.monitor(task)
        assert_receive {:DOWN, ^ref, :process, ^task, _reason}, 2_000
      end

      Application.put_env(:shroud, :openpanel, previous)
    end)

    %{bypass: bypass}
  end

  test "profile IDs are stable, account-specific HMACs derived from the server secret" do
    config = Application.fetch_env!(:shroud, ShroudWeb.Endpoint)
    on_exit(fn -> ShroudWeb.Endpoint.config_change([{ShroudWeb.Endpoint, config}], []) end)

    ShroudWeb.Endpoint.config_change(
      [{ShroudWeb.Endpoint, Keyword.put(config, :secret_key_base, "analytics-test-secret")}],
      []
    )

    assert Analytics.profile_id(42) ==
             "381ff32ac89f7f5547be696c204e051f6fd4f624dc9dd4bc608e896b8554f35f"

    assert Analytics.profile_id(42) == Analytics.profile_id(42)
    refute Analytics.profile_id(42) == Analytics.profile_id(43)

    ShroudWeb.Endpoint.config_change(
      [{ShroudWeb.Endpoint, Keyword.put(config, :secret_key_base, "another-analytics-secret")}],
      []
    )

    refute Analytics.profile_id(42) ==
             "381ff32ac89f7f5547be696c204e051f6fd4f624dc9dd4bc608e896b8554f35f"
  end

  test "payloads contain only pseudonymous ID, event, timestamp and custom-domain boolean", %{
    bypass: bypass
  } do
    owner = self()

    Bypass.expect(bypass, "POST", "/api/track", fn conn ->
      assert Plug.Conn.get_req_header(conn, "openpanel-client-id") == ["test-client"]
      assert Plug.Conn.get_req_header(conn, "openpanel-client-secret") == ["test-secret"]
      assert Plug.Conn.get_req_header(conn, "user-agent") == ["ShroudAnalytics/1.0"]
      assert Plug.Conn.get_req_header(conn, "x-client-ip") == []
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:payload, Jason.decode!(body)})
      Plug.Conn.resp(conn, 200, "{}")
    end)

    for domain_id <- [nil, 17] do
      assert :ok =
               Analytics.alias_created(%{
                 user_id: 42,
                 domain_id: domain_id,
                 address: "private@example.com"
               })

      assert_receive {:payload, %{"type" => "track", "payload" => payload}}, 2_000
      assert Map.keys(payload) |> Enum.sort() == ["name", "profileId", "properties"]
      assert payload["profileId"] == Analytics.profile_id(42)
      assert payload["name"] == "alias_created"
      assert Map.keys(payload["properties"]) |> Enum.sort() == ["__timestamp", "custom_domain"]
      assert payload["properties"]["custom_domain"] == not is_nil(domain_id)
      assert {:ok, _, _} = DateTime.from_iso8601(payload["properties"]["__timestamp"])
    end

    for {name, call} <- [
          {"email_forwarded", fn -> Analytics.email_forwarded(42) end},
          {"outgoing_email_sent", fn -> Analytics.outgoing_email_sent(42) end}
        ] do
      assert :ok = call.()
      assert_receive {:payload, %{"type" => "track", "payload" => payload}}, 2_000
      assert payload["name"] == name
      assert payload["profileId"] == Analytics.profile_id(42)
      assert Map.keys(payload["properties"]) == ["__timestamp"]
    end
  end

  test "lifetime redemption emits a conversion with its source only once", %{bypass: bypass} do
    owner = self()
    user = user_fixture()

    Bypass.expect_once(bypass, "POST", "/api/track", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:lifetime_conversion, Jason.decode!(body)})
      Plug.Conn.resp(conn, 200, "{}")
    end)

    assert :ok = Shroud.Billing.redeem_lifetime_code(Shroud.Billing.create_lifetime_code(), user)
    assert_receive {:lifetime_conversion, %{"payload" => payload}}, 2_000
    assert payload["name"] == "paid_conversion"
    assert payload["profileId"] == Analytics.profile_id(user.id)

    assert payload["properties"] == %{
             "source" => "lifetime_code",
             "__timestamp" => DateTime.to_iso8601(Repo.reload!(user).paid_converted_at)
           }

    assert :ok = Shroud.Billing.redeem_lifetime_code(Shroud.Billing.create_lifetime_code(), user)
  end

  test "a successfully persisted alias emits once; a duplicate creation does not", %{
    bypass: bypass
  } do
    owner = self()

    Bypass.expect_once(bypass, "POST", "/api/track", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:alias_event, Jason.decode!(body)})
      Plug.Conn.resp(conn, 200, "{}")
    end)

    user = user_fixture()
    attrs = %{user_id: user.id, address: "analytics@#{Shroud.Util.email_domain()}"}
    assert {:ok, email_alias} = Shroud.Aliases.create_email_alias(attrs)
    assert Repo.get!(Shroud.Aliases.EmailAlias, email_alias.id)
    assert_receive {:alias_event, %{"payload" => payload}}, 2_000
    assert payload["name"] == "alias_created"
    assert payload["profileId"] == Analytics.profile_id(user.id)
    assert payload["properties"]["custom_domain"] == false
    assert {:error, _} = Shroud.Aliases.create_email_alias(attrs)
  end

  test "disabled or missing-secret configuration does not start a network task" do
    config = Application.fetch_env!(:shroud, :openpanel)

    for overrides <- [[enabled: false], [client_secret: nil], [client_secret: ""]] do
      Application.put_env(:shroud, :openpanel, Keyword.merge(config, overrides))
      assert :ok = Analytics.email_forwarded(42)
      assert Task.Supervisor.children(Shroud.Analytics.Tasks) == []
    end
  end

  test "the lifecycle returns while ingestion is blocked and rejected requests are not retried",
       %{bypass: bypass} do
    owner = self()

    Bypass.expect_once(bypass, "POST", "/api/track", fn conn ->
      send(owner, {:request_waiting, self()})
      receive do: (:release -> Plug.Conn.resp(conn, 503, "unavailable"))
    end)

    assert :ok = Analytics.email_forwarded(42)
    assert_receive {:request_waiting, handler}, 2_000
    [task] = Task.Supervisor.children(Shroud.Analytics.Tasks)
    ref = Process.monitor(task)
    send(handler, :release)
    assert_receive {:DOWN, ^ref, :process, ^task, :normal}, 2_000
  end

  test "conversion survives out-of-order billing events and emits only once", %{bypass: bypass} do
    owner = self()

    Bypass.expect_once(bypass, "POST", "/api/track", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)["payload"]
      assert payload["name"] == "paid_conversion"

      assert payload["properties"] == %{
               "source" => "paddle",
               "__timestamp" => "2026-10-01T12:00:00.000000Z"
             }

      send(owner, :conversion)
      Plug.Conn.resp(conn, 200, "{}")
    end)

    user =
      user_fixture(%{
        status: :active,
        paddle_customer_id: "ctm_analytics",
        paddle_subscription_id: "sub_analytics",
        paddle_price_id: "pri_analytics",
        last_paddle_event_at: ~N[2026-10-02 12:00:00]
      })

    event = %{
      customer_id: "ctm_analytics",
      identity_user_id: user.id,
      subscription_id: "sub_analytics",
      price_id: "pri_analytics",
      status: :active,
      plan_expires_at: ~N[2026-11-01 12:00:00],
      event_at: ~N[2026-10-01 12:00:00],
      paid_conversion?: true
    }

    assert {:ok, :stale} = Accounts.apply_paddle_subscription_event(event)
    assert_receive :conversion, 2_000
    updated = Repo.reload!(user)
    assert updated.paid_converted_at == ~U[2026-10-01 12:00:00.000000Z]
    assert updated.last_paddle_event_at == ~N[2026-10-02 12:00:00.000000]
    assert {:ok, :stale} = Accounts.apply_paddle_subscription_event(event)

    assert {:ok, :applied} =
             Accounts.apply_paddle_subscription_event(%{
               event
               | event_at: ~N[2026-10-03 12:00:00]
             })

    assert Repo.reload!(user).paid_converted_at == updated.paid_converted_at
  end
end
