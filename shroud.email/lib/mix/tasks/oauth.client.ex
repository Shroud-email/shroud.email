defmodule Mix.Tasks.Oauth.Client do
  use Mix.Task
  alias Shroud.Mcp.Clients

  @shortdoc "Provision a public OAuth client with PKCE and exact callbacks"
  @moduledoc """
  Run `mix oauth.client --id UUID --name NAME --resource api --redirect-uri HTTPS_URL`.
  Use `--resource mcp` for a predefined MCP client. Repeat `--redirect-uri` for
  multiple callbacks. Provisioning an existing registered ID updates its name
  and callbacks without changing the ID or revoking active connections.
  """

  @impl true
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [id: :string, name: :string, resource: :string, redirect_uri: :keep]
      )

    resource =
      case opts[:resource] do
        "api" -> "/api/v1"
        "mcp" -> "/mcp"
        _ -> nil
      end

    redirects = Keyword.get_values(opts, :redirect_uri)

    if rest != [] or invalid != [] or resource == nil or
         not Enum.all?([:id, :name], &Keyword.has_key?(opts, &1)) or
         redirects == [] do
      Mix.raise(
        "Usage: mix oauth.client --id UUID --name NAME --resource api|mcp --redirect-uri HTTPS_URL"
      )
    end

    Mix.Task.run("app.start")
    client = Clients.provision!(opts[:id], opts[:name], resource, redirects)

    Mix.shell().info(
      "Provisioned public OAuth client #{client.id} (#{resource}); PKCE S256 required."
    )
  end
end
