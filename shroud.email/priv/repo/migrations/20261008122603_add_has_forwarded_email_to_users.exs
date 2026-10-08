defmodule Shroud.Repo.Migrations.AddHasForwardedEmailToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :has_forwarded_email, :boolean, default: false, null: false
    end

    flush()

    execute("""
    UPDATE users SET has_forwarded_email = true
    WHERE EXISTS (
      SELECT 1 FROM email_aliases
      WHERE email_aliases.user_id = users.id AND email_aliases.forwarded > 0
    )
    """)
  end

  def down do
    alter table(:users) do
      remove :has_forwarded_email
    end
  end
end
