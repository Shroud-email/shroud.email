defmodule Shroud.Repo.Migrations.AddMcpConnections do
  use Ecto.Migration

  def change do
    create unique_index(:oauth_clients, [:name])

    create table(:mcp_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :client_id, :text, null: false
      add :resource, :text, null: false
      add :scopes, {:array, :text}, null: false
      add :code_id, references(:oauth_tokens, type: :uuid, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:mcp_connections, [:user_id])

    create table(:mcp_connection_tokens, primary_key: false) do
      add :connection_id, references(:mcp_connections, on_delete: :delete_all), null: false

      add :token_id, references(:oauth_tokens, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true
    end

    create index(:mcp_connection_tokens, [:connection_id])
  end
end
