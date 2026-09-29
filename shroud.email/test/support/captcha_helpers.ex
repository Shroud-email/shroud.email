defmodule ShroudWeb.CaptchaHelpers do
  @moduledoc """
  Test helpers for the optional Cap CAPTCHA integration. These mutate
  global `Application` env, so tests using them MUST run with `async: false`
  (the Cap controller tests already do).
  """

  def enable_cap do
    Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
    Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
    Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
  end

  def disable_cap do
    Application.put_env(:shroud, :cap_instance_url, nil)
    Application.put_env(:shroud, :cap_site_key, nil)
    Application.put_env(:shroud, :cap_secret_key, nil)
  end
end
