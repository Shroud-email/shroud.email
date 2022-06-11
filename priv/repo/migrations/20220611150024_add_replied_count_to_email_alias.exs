defmodule Shroud.Repo.Migrations.AddRepliedCountToEmailAlias do
  use Ecto.Migration

  def change do
    alter table(:email_aliases) do
      add :replied, :integer, default: 0, null: false
    end

    alter table(:email_metrics) do
      add :replied, :integer, default: 0, null: false
    end
  end
end
