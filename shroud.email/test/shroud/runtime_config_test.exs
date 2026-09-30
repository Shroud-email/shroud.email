defmodule Shroud.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @optional_variables ~w(SENTRY_DSN PADDLE_ENVIRONMENT PADDLE_API_KEY PADDLE_WEBHOOK_SECRET PADDLE_YEARLY_PRICE_ID PADDLE_CLIENT_TOKEN CAP_INSTANCE_URL CAP_SITE_KEY CAP_SECRET_KEY)
  @required_variables %{
    "APP_DOMAIN" => "app.example.com",
    "EMAIL_DOMAIN" => "example.com",
    "DATABASE_URL" => "ecto://postgres:postgres@localhost/shroud_test",
    "DB_ENCRYPTION_KEY" => Base.encode64(String.duplicate("k", 32)),
    "SECRET_KEY_BASE" => String.duplicate("s", 64),
    "SMTP_USERNAME" => "shroud",
    "SMTP_PASSWORD" => "test-password"
  }

  setup do
    previous =
      Map.new(@optional_variables ++ Map.keys(@required_variables), &{&1, System.get_env(&1)})

    Enum.each(@optional_variables, &System.delete_env/1)
    System.put_env(@required_variables)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "production accepts absent optional integrations" do
    assert_integrations_disabled()
  end

  test "production accepts blank optional integrations" do
    System.put_env(Map.new(@optional_variables, &{&1, ""}))
    # Without an explicit dsn: nil, Sentry's environment fallback rejects "".
    assert_raise ArgumentError, ~r/invalid configuration/, fn -> Sentry.Config.validate!([]) end
    assert_integrations_disabled()
  end

  defp assert_integrations_disabled do
    config = read_config()
    assert config[:sentry][:dsn] == nil
    # Validate against Sentry itself: it also reads the blank environment var.
    assert Sentry.Config.validate!(config[:sentry])[:dsn] == nil
    billing = config[:shroud][:billing]
    assert billing[:paddle_api_key] == nil
    assert billing[:paddle_webhook_secret] == nil
    assert billing[:paddle_yearly_price_id] == nil
    assert billing[:paddle_environment] == "live"
    assert billing[:paddle_base_url] == "https://api.paddle.com"
  end

  test "configured Sentry and sandbox Paddle retain their settings" do
    System.put_env(%{
      "SENTRY_DSN" => "https://public@sentry.example.com/1",
      "PADDLE_ENVIRONMENT" => "sandbox",
      "PADDLE_API_KEY" => "api-key",
      "PADDLE_WEBHOOK_SECRET" => "webhook-secret",
      "PADDLE_YEARLY_PRICE_ID" => "pri_yearly",
      "PADDLE_CLIENT_TOKEN" => "client-token"
    })

    config = read_config()
    assert config[:sentry][:dsn] == "https://public@sentry.example.com/1"
    assert config[:sentry][:integrations][:oban][:capture_errors]
    assert config[:shroud][:billing][:paddle_environment] == "sandbox"
    assert config[:shroud][:billing][:paddle_base_url] == "https://sandbox-api.paddle.com"
    assert config[:shroud][:billing][:paddle_api_key] == "api-key"
  end

  test "partially configured Paddle still fails fast" do
    System.put_env("PADDLE_CLIENT_TOKEN", "client-token")

    assert_raise RuntimeError, ~r/PADDLE_API_KEY is required/, &read_config/0
  end

  test "invalid Paddle environment still fails fast" do
    System.put_env("PADDLE_ENVIRONMENT", "production")

    assert_raise RuntimeError, ~r/PADDLE_ENVIRONMENT must be either/, &read_config/0
  end

  defp read_config do
    Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
  end
end
