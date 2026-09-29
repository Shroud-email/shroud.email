defmodule Shroud.Repo.Migrations.CreateCustomDomains do
  use Ecto.Migration

  def change do
    create table(:custom_domains) do
      add :domain, :text, null: false
      add :verification_code, :text, null: false
      add :ownership_verified_at, :naive_datetime
      add :mx_verified_at, :naive_datetime
      add :spf_verified_at, :naive_datetime
      add :dkim_verified_at, :naive_datetime
      add :dmarc_verified_at, :naive_datetime
      add :catchall_enabled, :boolean, default: false, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:custom_domains, [:user_id])
    create unique_index(:custom_domains, [:domain])
  end
end
