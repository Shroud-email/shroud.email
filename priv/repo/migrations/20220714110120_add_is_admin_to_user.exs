defmodule Shroud.Repo.Migrations.AddIsAdminToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
    end
  end
end
