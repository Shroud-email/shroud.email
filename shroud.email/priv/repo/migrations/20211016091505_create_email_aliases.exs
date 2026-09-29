defmodule Shroud.Repo.Migrations.CreateEmailAliases do
  use Ecto.Migration

  def change do
    create table(:email_aliases) do
      add :address, :string
      add :enabled, :boolean, default: true, null: false
      add :user_id, references("users", on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:email_aliases, [:address])
    create index(:email_aliases, [:user_id])
  end
end
