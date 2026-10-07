defmodule Shroud.Repo.Migrations.CreateEmailUnsubscribeRelays do
  use Ecto.Migration

  def change do
    create table(:email_unsubscribe_relays) do
      add :token_hash, :binary, null: false
      add :recipe, :binary, null: false
      add :generation, :integer, null: false
      add :alias_id, references(:email_aliases, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:email_unsubscribe_relays, [:token_hash])
    create index(:email_unsubscribe_relays, [:alias_id])
  end
end
