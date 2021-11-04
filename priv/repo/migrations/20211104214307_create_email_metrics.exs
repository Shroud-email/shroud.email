defmodule Shroud.Repo.Migrations.CreateEmailMetrics do
  use Ecto.Migration

  def change do
    create table(:email_metrics) do
      add :date, :date, null: false
      add :forwarded, :integer, default: 0, null: false
      add :alias_id, references(:email_aliases, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:email_metrics, [:alias_id])
    create unique_index(:email_metrics, [:alias_id, :date])
  end
end
