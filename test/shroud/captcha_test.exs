defmodule Shroud.CaptchaTest do
  # Mutates global Application env (cap_*) that other tests read via
  # Captcha.enabled?/0, so it must run serially to stay isolation-safe.
  use ExUnit.Case, async: false

  import Req.Test

  alias Shroud.Captcha

  # Helper: set all three env vars so enabled?/0 is true.
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

  # config/test.exs sets cap_req_options: [plug: {Req.Test, Shroud.Captcha}].
  # Req.Test routes the POST through our stub. The plug receives a Plug.Conn
  # for the siteverify request; we read nothing from it and just return JSON.
  defp siteverify_response(body) do
    fn conn ->
      Req.Test.json(conn, body)
    end
  end

  describe "enabled?/0" do
    test "true when all three env vars are set" do
      enable_cap()
      assert Captcha.enabled?()
    after
      disable_cap()
    end

    test "false when any env var is nil" do
      disable_cap()
      refute Captcha.enabled?()

      Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
      refute Captcha.enabled?()
    after
      disable_cap()
    end

    test "false when env vars are empty strings (as example.env sets)" do
      Application.put_env(:shroud, :cap_instance_url, "")
      Application.put_env(:shroud, :cap_site_key, "")
      Application.put_env(:shroud, :cap_secret_key, "")
      refute Captcha.enabled?()

      # Two set, one empty -> still disabled.
      Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
      Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
      Application.put_env(:shroud, :cap_secret_key, "")
      refute Captcha.enabled?()
    after
      disable_cap()
    end

    test "false when env vars are whitespace-only strings" do
      Application.put_env(:shroud, :cap_instance_url, "   ")
      Application.put_env(:shroud, :cap_site_key, " \t ")
      Application.put_env(:shroud, :cap_secret_key, "\n")
      refute Captcha.enabled?()
    after
      disable_cap()
    end
  end

  describe "widget_endpoint/0" do
    test "returns instance + site key with trailing slash when enabled" do
      enable_cap()
      assert Captcha.widget_endpoint() == "https://cap.example.com/a1b2c3d4e5/"
    after
      disable_cap()
    end

    test "returns nil when disabled" do
      disable_cap()
      assert Captcha.widget_endpoint() == nil
    end
  end

  describe "verify/1" do
    test "returns :ok when Cap responds success: true" do
      enable_cap()
      stub(Shroud.Captcha, siteverify_response(%{"success" => true}))

      assert Captcha.verify("valid-token") == :ok
    after
      disable_cap()
    end

    test "returns {:error, :verification_failed} when success: false" do
      enable_cap()

      stub(
        Shroud.Captcha,
        siteverify_response(%{"success" => false, "error" => "Token not found"})
      )

      assert Captcha.verify("bad-token") == {:error, :verification_failed}
    after
      disable_cap()
    end

    test "returns {:error, :missing_token} when token is nil" do
      enable_cap()
      assert Captcha.verify(nil) == {:error, :missing_token}
    after
      disable_cap()
    end

    test "returns {:error, :missing_token} when token is empty" do
      enable_cap()
      assert Captcha.verify("") == {:error, :missing_token}
    after
      disable_cap()
    end

    test "returns {:error, :network_error} on transport error (fail-closed)" do
      enable_cap()

      stub(Shroud.Captcha, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert Captcha.verify("some-token") == {:error, :network_error}
    after
      disable_cap()
    end

    test "returns {:error, :verification_failed} (not a crash) when Cap is disabled" do
      disable_cap()
      assert Captcha.verify("some-token") == {:error, :verification_failed}
    after
      disable_cap()
    end

    test "returns {:error, :verification_failed} when given a non-binary token with Cap enabled" do
      enable_cap()
      assert Captcha.verify(["not", "a", "binary"]) == {:error, :verification_failed}
      assert Captcha.verify(%{"response" => "map"}) == {:error, :verification_failed}
    after
      disable_cap()
    end
  end
end
