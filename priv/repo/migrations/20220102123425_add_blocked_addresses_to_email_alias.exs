defmodule Shroud.Repo.Migrations.AddBlockedAddressesToEmailAlias do
  use Ecto.Migration

  def change do
    alter table(:email_aliases) do
      add :blocked_addresses, {:array, :text}, default: [], null: false
      add :blocked, :integer, default: 0, null: false
    end

    alter table(:email_metrics) do
      add :blocked, :integer, default: 0, null: false
    end
  end
end
