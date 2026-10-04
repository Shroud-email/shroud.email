defmodule Mix.Tasks.Oauth.ClientTest do
  use Shroud.DataCase, async: false

  import ExUnit.CaptureIO
  alias Mix.Tasks.Oauth.Client
  alias Shroud.Mcp.Clients

  test "provisions stable public API clients with every repeated callback and updates in place" do
    id = Ecto.UUID.generate()

    callbacks = [
      "https://app.shroud.email/oauth/callback",
      "https://extension.chromiumapp.org/oauth/callback"
    ]

    args = ["--id", id, "--name", "Mobile", "--resource", "api"]
    redirects = Enum.flat_map(callbacks, &["--redirect-uri", &1])

    assert capture_io(fn -> Client.run(args ++ redirects) end) =~
             "Provisioned public OAuth client #{id} (/api/v1); PKCE S256 required."

    assert %{
             "name" => "Mobile",
             "registered" => true,
             "resource_path" => "/api/v1",
             "redirect_uris" => ^callbacks
           } = Clients.metadata(id)

    client = Clients.get_client(id)
    assert client.pkce and client.public_refresh_token and client.public_revoke

    updated = [
      "--id",
      id,
      "--name",
      "Renamed",
      "--resource",
      "api",
      "--redirect-uri",
      hd(callbacks)
    ]

    capture_io(fn -> Client.run(updated) end)
    assert %{"name" => "Renamed", "redirect_uris" => [callback]} = Clients.metadata(id)
    assert callback == hd(callbacks)
    assert Repo.aggregate(Boruta.Ecto.Client, :count, :id) == 1
  end

  test "provisions predefined MCP clients without granting REST registration" do
    id = Ecto.UUID.generate()

    capture_io(fn ->
      Client.run([
        "--id",
        id,
        "--name",
        "ChatGPT",
        "--resource",
        "mcp",
        "--redirect-uri",
        "https://openai.example/callback"
      ])
    end)

    assert %{"registered" => true, "resource_path" => "/mcp"} = Clients.metadata(id)
  end

  test "rejects incomplete or unknown arguments before writing clients" do
    args = [
      "--id",
      Ecto.UUID.generate(),
      "--name",
      "Mobile",
      "--resource",
      "api",
      "--redirect-uri",
      "https://app.shroud.email/oauth/callback"
    ]

    for invalid <- [
          [],
          args ++ ["extra"],
          args ++ ["--unknown", "value"],
          List.replace_at(args, 5, "other"),
          Enum.take(args, 6)
        ] do
      assert_raise Mix.Error, ~r/Usage: mix oauth.client/, fn -> Client.run(invalid) end
    end

    assert Repo.aggregate(Boruta.Ecto.Client, :count, :id) == 0
  end
end
