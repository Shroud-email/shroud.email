defmodule Shroud.Repo.Migrations.AddThemeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :theme, :string, default: "system", null: false
    end
  end
end
