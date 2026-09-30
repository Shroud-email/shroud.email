defmodule Shroud.RuntimeConfigTest do
  use ExUnit.Case, async: false

  setup do
    env = %{
      "APP_DOMAIN" => "staging.example.com",
      "DATABASE_URL" => "ecto://user:password@localhost/shroud_staging",
      "DB_ENCRYPTION_KEY" => Base.encode64(String.duplicate("a", 32)),
      "SECRET_KEY_BASE" => String.duplicate("b", 64),
      "SMTP_USERNAME" => "test",
      "SMTP_PASSWORD" => "test",
      "EMAIL_DOMAIN" => "mail.staging.example.com",
      "PADDLE_API_KEY" => nil,
      "PADDLE_WEBHOOK_SECRET" => nil,
      "PADDLE_YEARLY_PRICE_ID" => nil,
      "PADDLE_CLIENT_TOKEN" => nil,
      "PADDLE_ENVIRONMENT" => nil,
      "SENTRY_DSN" => "https://public@example.com/1",
      "SENTRY_ENVIRONMENT" => nil
    }

    original_env = Map.new(env, fn {key, _value} -> {key, System.get_env(key)} end)
    on_exit(fn -> Enum.each(original_env, fn {key, value} -> put_env(key, value) end) end)
    Enum.each(env, fn {key, value} -> put_env(key, value) end)
    :ok
  end

  test "Sentry is disabled with a missing or empty DSN, even with a staging label" do
    System.put_env("SENTRY_ENVIRONMENT", "staging")

    for dsn <- [nil, ""] do
      put_env("SENTRY_DSN", dsn)
      config = read_config()
      assert Keyword.fetch!(config[:sentry], :dsn) == nil
      assert System.get_env("SENTRY_DSN") == nil
      assert config[:shroud][:env] == :prod
    end
  end

  test "Sentry defaults to prod with a missing or empty environment name" do
    for environment <- [nil, ""] do
      put_env("SENTRY_ENVIRONMENT", environment)
      assert read_config()[:sentry][:environment_name] == :prod
    end
  end

  test "Sentry uses the staging label without changing the Elixir environment" do
    System.put_env("SENTRY_ENVIRONMENT", "staging")
    config = read_config()

    assert config[:sentry][:dsn] == "https://public@example.com/1"
    assert config[:sentry][:environment_name] == "staging"
    assert config[:shroud][:env] == :prod
  end

  defp read_config do
    Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__),
      env: :prod,
      target: :host
    )
  end

  defp put_env(key, nil), do: System.delete_env(key)
  defp put_env(key, value), do: System.put_env(key, value)
end
