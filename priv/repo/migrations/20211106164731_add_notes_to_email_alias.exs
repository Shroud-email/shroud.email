defmodule Shroud.Repo.Migrations.AddNotesToEmailAlias do
  use Ecto.Migration

  def change do
    alter table(:email_aliases) do
      add :title, :string
      add :notes, :text
    end
  end
end
