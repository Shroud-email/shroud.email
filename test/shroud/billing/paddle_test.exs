defmodule Shroud.Billing.PaddleTest do
  use ExUnit.Case, async: false

  alias Shroud.Billing.Paddle

  # Configured in config/test.exs
  @secret Application.compile_env!(:shroud, [:billing, :paddle_webhook_secret])

  describe "verify_webhook/2" do
    test "returns {:ok, event} for a valid signature" do
      payload = ~s({"event_id":"evt_1","event_type":"subscription.created","data":{}})
      ts = System.system_time(:second)
      signature = sign(ts, payload)

      header = "ts=#{ts};h1=#{signature}"

      assert {:ok, event} = Paddle.verify_webhook(payload, header)
      assert event["event_type"] == "subscription.created"
    end

    test "returns {:error, :invalid_signature} for a bad signature" do
      payload = ~s({"event_id":"evt_1"})
      header = "ts=#{System.system_time(:second)};h1=#{String.duplicate("0", 64)}"

      assert {:error, :invalid_signature} = Paddle.verify_webhook(payload, header)
    end

    test "returns {:error, :stale} for an old timestamp" do
      payload = ~s({"event_id":"evt_1"})
      old_ts = System.system_time(:second) - 100
      signature = sign(old_ts, payload)

      header = "ts=#{old_ts};h1=#{signature}"

      assert {:error, :stale} = Paddle.verify_webhook(payload, header)
    end

    test "returns {:error, :malformed} for a bad header" do
      assert {:error, :malformed} = Paddle.verify_webhook("body", "not-a-valid-header")
    end

    test "returns {:error, :malformed} for signed invalid JSON" do
      payload = "not-json"
      ts = System.system_time(:second)

      assert {:error, :malformed} =
               Paddle.verify_webhook(payload, "ts=#{ts};h1=#{sign(ts, payload)}")
    end

    test "returns {:error, :malformed} for a signed non-object JSON payload" do
      payload = ~s(["subscription.created"])
      ts = System.system_time(:second)

      assert {:error, :malformed} =
               Paddle.verify_webhook(payload, "ts=#{ts};h1=#{sign(ts, payload)}")
    end

    test "accepts any valid h1 signature during secret rotation" do
      payload = ~s({"event_id":"evt_1"})
      ts = System.system_time(:second)
      valid_signature = sign(ts, payload)
      invalid_signature = String.duplicate("0", 64)

      assert {:ok, _event} =
               Paddle.verify_webhook(
                 payload,
                 "ts=#{ts};h1=#{valid_signature};h1=#{invalid_signature}"
               )

      assert {:ok, _event} =
               Paddle.verify_webhook(
                 payload,
                 "ts=#{ts};h1=#{invalid_signature};h1=#{valid_signature}"
               )
    end
  end

  test "reports unavailable instead of raising when optional billing config is absent" do
    original = Application.fetch_env!(:shroud, :billing)
    Application.delete_env(:shroud, :billing)
    on_exit(fn -> Application.put_env(:shroud, :billing, original) end)

    refute Paddle.checkout_configured?()
    assert {:error, :not_configured} = Paddle.verify_webhook("{}", "ts=1;h1=invalid")
    assert {:error, :not_configured} = Paddle.create_checkout_transaction("identity")
  end

  # Mirrors the Paddle signature scheme: HMAC-SHA256(secret, ts:body), hex.
  defp sign(ts, payload) do
    :crypto.mac(:hmac, :sha256, @secret, "#{ts}:#{payload}")
    |> Base.encode16(case: :lower)
  end
end

defmodule Shroud.Billing.PaddleHTTPTest do
  use ExUnit.Case, async: false

  alias Shroud.Billing.Paddle

  # For HTTP-bound tests we stub at the Req level using Bypass; verify the
  # request shape (URL, auth, body) and the response shaping.
  setup do
    # Point the client at a Bypass server for the test.
    bypass = Bypass.open()
    original = Application.get_env(:shroud, :billing)

    Application.put_env(
      :shroud,
      :billing,
      Keyword.merge(original,
        paddle_base_url: "http://localhost:#{bypass.port}",
        paddle_api_key: "test_key",
        paddle_yearly_price_id: "pri_test_yearly"
      )
    )

    on_exit(fn -> Application.put_env(:shroud, :billing, original) end)
    {:ok, bypass: bypass}
  end

  describe "create_portal_session/1" do
    test "posts to /customers/{id}/portal-sessions and returns the overview url", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/customers/ctm_123/portal-sessions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body in ["{}", ""], "portal session should send an empty body"

        Resp.json(conn, 201, %{
          "data" => %{"urls" => %{"general" => %{"overview" => "https://portal.paddle.com/..."}}}
        })
      end)

      assert {:ok, %{url: "https://portal.paddle.com/..."}} =
               Paddle.create_portal_session("ctm_123")
    end

    test "returns {:error, {:paddle_api, status, code}} for a non-201 response", %{
      bypass: bypass
    } do
      Bypass.expect(bypass, "POST", "/customers/ctm_123/portal-sessions", fn conn ->
        Resp.json(conn, 404, %{"error" => %{"code" => "not_found"}})
      end)

      assert {:error, {:paddle_api, 404, "not_found"}} =
               Paddle.create_portal_session("ctm_123")
    end
  end

  describe "create_checkout_transaction/1" do
    test "creates the configured yearly transaction with a server-signed identity", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/transactions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body) == %{
                 "items" => [%{"price_id" => "pri_test_yearly", "quantity" => 1}],
                 "custom_data" => %{"shroud_checkout_identity" => "signed-identity"}
               }

        Resp.json(conn, 201, %{"data" => %{"id" => "txn_123"}})
      end)

      assert {:ok, %{id: "txn_123"}} =
               Paddle.create_checkout_transaction("signed-identity")
    end
  end

  describe "get_transaction/1" do
    test "returns the transaction status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/transactions/txn_pending", fn conn ->
        Resp.json(conn, 200, %{
          "data" => %{"id" => "txn_pending", "status" => "draft"}
        })
      end)

      assert {:ok, %{id: "txn_pending", status: "draft"}} =
               Paddle.get_transaction("txn_pending")
    end
  end
end

defmodule Resp do
  def json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
