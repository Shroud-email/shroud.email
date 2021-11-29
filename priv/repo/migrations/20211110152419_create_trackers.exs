defmodule Shroud.Repo.Migrations.CreateTrackers do
  use Ecto.Migration

  def change do
    create table(:trackers) do
      add :name, :string
      add :pattern, :string

      timestamps()
    end

    create unique_index(:trackers, [:name, :pattern])
  end
end
