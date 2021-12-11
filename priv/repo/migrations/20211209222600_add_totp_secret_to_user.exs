defmodule Shroud.Repo.Migrations.AddTotpFieldsToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :totp_secret, :binary
    end
  end
end
