defmodule Shroud.Repo.Migrations.AddTotpBackupCodesToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :totp_backup_codes, :binary
      add :totp_enabled, :boolean, null: false, default: false
    end
  end
end
