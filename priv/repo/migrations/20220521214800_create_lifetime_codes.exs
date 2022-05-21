defmodule Shroud.Repo.Migrations.CreateLifetimeCodes do
  use Ecto.Migration

  def change do
    create table(:lifetime_codes) do
      add :code, :string
      add :redeemed_by_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create unique_index(:lifetime_codes, [:code])
    create index(:lifetime_codes, [:redeemed_by_id])
  end
end
