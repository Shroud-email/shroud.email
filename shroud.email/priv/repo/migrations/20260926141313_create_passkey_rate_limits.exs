defmodule Shroud.Repo.Migrations.CreatePasskeyRateLimits do
  use Ecto.Migration

  def change do
    create table(:passkey_rate_limits, primary_key: false) do
      add :source, :binary, null: false
      add :minute, :bigint, null: false
      add :attempts, :integer, null: false
    end

    create unique_index(:passkey_rate_limits, [:source, :minute])
    create index(:passkey_rate_limits, [:minute])
  end
end
