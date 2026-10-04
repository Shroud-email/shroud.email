defmodule Shroud.Repo.Migrations.RenameOauthConnectionTables do
  use Ecto.Migration

  def change do
    rename table(:mcp_connections), to: table(:oauth_connections)
    rename table(:mcp_connection_tokens), to: table(:oauth_connection_tokens)
  end
end
