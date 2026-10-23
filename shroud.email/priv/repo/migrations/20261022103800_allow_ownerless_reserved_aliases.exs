defmodule Shroud.Repo.Migrations.AllowOwnerlessReservedAliases do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE email_aliases ALTER COLUMN user_id DROP NOT NULL",
      "ALTER TABLE email_aliases ALTER COLUMN user_id SET NOT NULL"
    )
  end
end
