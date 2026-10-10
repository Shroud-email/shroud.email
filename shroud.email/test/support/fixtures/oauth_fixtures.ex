defmodule Shroud.OAuthFixtures do
  alias Shroud.{Accounts, OAuth, Repo}
  import Shroud.AccountsFixtures

  def client_fixture(callback \\ "https://client.example/callback") do
    {:ok, registration} =
      OAuth.Clients.register(%{"client_name" => "Test client", "redirect_uris" => [callback]})

    registration.client_id
  end

  def authorization_params(
        scopes \\ Map.keys(OAuth.permissions(OAuth.resource(:mcp))),
        callback \\ "https://client.example/callback"
      ) do
    verifier = String.duplicate("a", 43)

    params = %{
      "client_id" => client_fixture(callback),
      "redirect_uri" => callback,
      "response_type" => "code",
      "scope" => Enum.join(scopes, " "),
      "state" => "user-supplied-state",
      "resource" => OAuth.resource(:mcp),
      "code_challenge_method" => "S256",
      "code_challenge" => :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    }

    {params, verifier}
  end

  def confirmed_user do
    user_fixture() |> Accounts.User.confirm_changeset() |> Repo.update!()
  end

  def connection_fixture(
        scopes \\ Map.keys(OAuth.permissions(OAuth.resource(:mcp))),
        user \\ confirmed_user()
      ) do
    {params, verifier} = authorization_params(scopes)
    {:ok, code} = OAuth.authorize(user, params)

    exchange =
      Map.merge(params, %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => verifier
      })

    {:ok, tokens} = OAuth.exchange(exchange)
    connection = OAuth.list_connections(user) |> hd()
    %{user: user, tokens: tokens, connection: connection, exchange: exchange}
  end
end
