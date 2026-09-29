defmodule Shroud.Repo.Migrations.RemoveTrialPlan do
  use Ecto.Migration

  def up do
    # Move any stragglers still on the (now-removed) trial tier to free.
    execute "UPDATE users SET status = 'free', trial_expires_at = NULL WHERE status = 'trial'"

    # Drop the trial column and remove 'trial' from the status enum.
    alter table(:users) do
      remove :trial_expires_at
    end

    execute "ALTER TYPE user_status RENAME TO user_status_old"

    execute """
    CREATE TYPE user_status AS ENUM ('lead', 'active', 'inactive', 'lifetime', 'free')
    """

    execute """
    ALTER TABLE users
      ALTER COLUMN status DROP DEFAULT,
      ALTER COLUMN status TYPE user_status USING status::text::user_status
    """

    execute "ALTER TABLE users ALTER COLUMN status SET DEFAULT 'lead'"
    execute "DROP TYPE user_status_old"
  end

  def down do
    execute "ALTER TYPE user_status RENAME TO user_status_old"

    execute """
    CREATE TYPE user_status AS ENUM ('lead', 'trial', 'active', 'inactive', 'lifetime', 'free')
    """

    execute """
    ALTER TABLE users
      ALTER COLUMN status DROP DEFAULT,
      ALTER COLUMN status TYPE user_status USING status::text::user_status
    """

    execute "ALTER TABLE users ALTER COLUMN status SET DEFAULT 'lead'"
    execute "DROP TYPE user_status_old"

    alter table(:users) do
      add :trial_expires_at, :naive_datetime
    end
  end
end
