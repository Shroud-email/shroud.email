defmodule Shroud.Repo.Migrations.AddUnsubscribePreferences do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :unsubscribe_behavior, :string, null: false, default: "forward_then_block"
    end

    alter table(:email_aliases) do
      add :unsubscribe_generation, :integer, null: false, default: 0
    end
  end
end
