defmodule Shroud.Repo.Migrations.AddEmailBrandingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :email_branding, :boolean, default: true, null: false
    end
  end
end
