defmodule Shroud.Repo.Migrations.AddLifetimeStatusToUser do
  use Ecto.Migration

  def change do
    execute("ALTER TYPE user_status ADD VALUE 'lifetime'")
  end
end
