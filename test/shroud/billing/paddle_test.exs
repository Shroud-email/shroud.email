defmodule Shroud.Billing.PaddleTest do
  use ExUnit.Case, async: true

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
  end

  # Mirrors the Paddle signature scheme: HMAC-SHA256(secret, ts:body), hex.
  defp sign(ts, payload) do
    :crypto.mac(:hmac, :sha256, @secret, "#{ts}:#{payload}")
    |> Base.encode16(case: :lower)
  end
end

defmodule Shroud.Billing.PaddleHTTPTest do
  use ExUnit.Case, async: true

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
               Shroud.Billing.Paddle.create_portal_session("ctm_123")
    end

    test "returns {:error, {:paddle_api, status, code}} for a non-201 response", %{
      bypass: bypass
    } do
      Bypass.expect(bypass, "POST", "/customers/ctm_123/portal-sessions", fn conn ->
        Resp.json(conn, 404, %{"error" => %{"code" => "not_found"}})
      end)

      assert {:error, {:paddle_api, 404, "not_found"}} =
               Shroud.Billing.Paddle.create_portal_session("ctm_123")
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
