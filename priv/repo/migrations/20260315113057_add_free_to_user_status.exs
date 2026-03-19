defmodule Shroud.Repo.Migrations.AddFreeToUserStatus do
  use Ecto.Migration

  def up do
    execute "ALTER TYPE user_status ADD VALUE IF NOT EXISTS 'free'"
  end

  def down do
    # Postgres does not support removing enum values; this is a no-op.
    :ok
  end
end
