defmodule Shroud.Repo.Migrations.CreateTrackerDomainMetrics do
  use Ecto.Migration

  def change do
    create table(:tracker_domain_metrics) do
      add :domain, :string, null: false
      add :date, :date, null: false
      add :count, :bigint, default: 0, null: false

      timestamps()
    end

    create unique_index(:tracker_domain_metrics, [:domain, :date])
  end
end
