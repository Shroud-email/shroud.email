defmodule Shroud.Repo.Migrations.CreatePasskeyChallenges do
  use Ecto.Migration

  def change do
    create table(:passkey_challenges) do
      add :token, :binary, null: false
      add :bytes, :binary, null: false
      add :kind, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :issued_at, :bigint, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create unique_index(:passkey_challenges, [:token])
    create index(:passkey_challenges, [:expires_at])
  end
end
