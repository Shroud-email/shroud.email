defmodule ShroudWeb.Plugs.VerifyCaptchaTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest
  import Req.Test

  alias Phoenix.Flash
  alias ShroudWeb.Plugs.VerifyCaptcha

  defp enable_cap do
    Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
    Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
    Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
  end

  defp disable_cap do
    Application.put_env(:shroud, :cap_instance_url, nil)
    Application.put_env(:shroud, :cap_site_key, nil)
    Application.put_env(:shroud, :cap_secret_key, nil)
  end

  # Build a Plug.Conn shaped like a Phoenix form POST: parsed params with a
  # "cap-token" key. We don't go through the router; we invoke the plug
  # directly so the test is focused on the plug's behavior.
  defp conn_with_token(token) do
    build_conn(:post, "/users/register", %{"cap-token" => token})
  end

  # `put_flash/3` (used inside the plug) requires `conn.assigns.flash` to
  # already exist. When invoking the plug directly outside a browser
  # pipeline we pre-populate it ourselves so we can assert on the result.
  defp for_plug(conn), do: assign(conn, :flash, %{})

  describe "when Cap is disabled" do
    test "passes the conn through unchanged (no-op)" do
      disable_cap()
      conn = conn_with_token("ignored-token")
      returned = VerifyCaptcha.call(conn, [])

      assert returned == conn
    after
      disable_cap()
    end
  end

  describe "when Cap is enabled" do
    test "passes through when verify returns :ok" do
      enable_cap()
      stub(Shroud.Captcha, fn conn -> Req.Test.json(conn, %{"success" => true}) end)

      conn = conn_with_token("valid-token")
      returned = VerifyCaptcha.call(conn, [])

      refute returned.halted
    after
      disable_cap()
    end

    test "rejects (flash + redirect + halt) when token is missing" do
      enable_cap()
      conn = build_conn(:post, "/users/register", %{}) |> for_plug()

      returned = VerifyCaptcha.call(conn, [])

      assert returned.halted
      assert Flash.get(returned.assigns.flash, :error) =~ "verification"
      assert redirected_to(returned) == "/users/register"
    after
      disable_cap()
    end

    test "rejects when verify returns {:error, :verification_failed}" do
      enable_cap()
      stub(Shroud.Captcha, fn conn -> Req.Test.json(conn, %{"success" => false}) end)

      returned = VerifyCaptcha.call(conn_with_token("bad-token") |> for_plug(), [])

      assert returned.halted
      assert Flash.get(returned.assigns.flash, :error) =~ "verification"
    after
      disable_cap()
    end

    test "rejects (fail-closed) when verify returns {:error, :network_error}" do
      enable_cap()
      stub(Shroud.Captcha, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      returned = VerifyCaptcha.call(conn_with_token("some-token") |> for_plug(), [])

      assert returned.halted
      assert Flash.get(returned.assigns.flash, :error) =~ "verification"
    after
      disable_cap()
    end
  end
end
