defmodule Shroud.McpConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("MCP_OAUTH_CLIENTS")

    on_exit(fn ->
      if previous,
        do: System.put_env("MCP_OAUTH_CLIENTS", previous),
        else: System.delete_env("MCP_OAUTH_CLIENTS")
    end)

    :ok
  end

  test "configured redirects allow HTTPS and loopback HTTP only" do
    for redirect <- [
          "https://client.example/callback",
          "http://localhost:1234/callback",
          "http://127.0.0.1:4321/callback",
          "http://[::1]:3456/callback"
        ] do
      clients = configure(redirect)
      config = Config.Reader.read!("config/runtime.exs", env: :test, target: :host)
      assert config[:shroud][:mcp_clients] == clients
    end

    for redirect <- [
          "http://client.example/callback",
          "http://localhost.evil.example/callback",
          "http://127.0.0.2:4321/callback",
          "http://[::2]:3456/callback",
          "http://user@localhost/callback",
          "http://localhost/callback#fragment",
          "https://client.example/call back"
        ] do
      configure(redirect)

      assert_raise RuntimeError, ~r/MCP_OAUTH_CLIENTS/, fn ->
        Config.Reader.read!("config/runtime.exs", env: :test, target: :host)
      end
    end
  end

  defp configure(redirect) do
    clients = %{"desktop" => %{"name" => "Desktop", "redirect_uris" => [redirect]}}
    System.put_env("MCP_OAUTH_CLIENTS", Jason.encode!(clients))
    clients
  end
end
