defmodule Shroud.McpFixtures do
  alias Shroud.{Accounts, Mcp, Repo}
  import Shroud.AccountsFixtures

  def configure_clients do
    previous = Application.get_env(:shroud, :mcp_clients)

    Application.put_env(:shroud, :mcp_clients, %{
      "test-client" => %{
        "name" => "Test client",
        "redirect_uris" => ["https://client.example/callback"]
      },
      "other-client" => %{
        "name" => "Other client",
        "redirect_uris" => ["https://other.example/callback"]
      }
    })

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: Application.put_env(:shroud, :mcp_clients, previous),
        else: Application.delete_env(:shroud, :mcp_clients)
    end)
  end

  def authorization_params(scopes \\ Map.keys(Mcp.permissions())) do
    verifier = String.duplicate("a", 43)

    params = %{
      "client_id" => "test-client",
      "redirect_uri" => "https://client.example/callback",
      "response_type" => "code",
      "scope" => Enum.join(scopes, " "),
      "state" => "user-supplied-state",
      "resource" => Mcp.resource(),
      "code_challenge_method" => "S256",
      "code_challenge" => :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    }

    {params, verifier}
  end

  def confirmed_user do
    user_fixture() |> Accounts.User.confirm_changeset() |> Repo.update!()
  end

  def connection_fixture(scopes \\ Map.keys(Mcp.permissions()), user \\ confirmed_user()) do
    {params, verifier} = authorization_params(scopes)
    {:ok, code} = Mcp.authorize(user, params)

    exchange =
      Map.merge(params, %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => verifier
      })

    {:ok, tokens} = Mcp.exchange(exchange)
    connection = Mcp.list_connections(user) |> hd()
    %{user: user, tokens: tokens, connection: connection, exchange: exchange}
  end
end
