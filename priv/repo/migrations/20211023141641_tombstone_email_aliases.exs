defmodule Shroud.Repo.Migrations.TombstoneEmailAliases do
  use Ecto.Migration

  def up do
    drop constraint(:email_aliases, "email_aliases_user_id_fkey")
    alter table(:email_aliases) do
      modify :user_id, references(:users, on_delete: :nilify_all)
      add :deleted_at, :naive_datetime
    end

    create index(:email_aliases, [:deleted_at])
  end

  def down do
    drop constraint(:email_aliases, "email_aliases_user_id_fkey")
    alter table(:email_aliases) do
      modify :user_id, references(:users, on_delete: :delete_all)
      remove :deleted_at
    end
  end
end
