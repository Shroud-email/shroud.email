defmodule Shroud.Repo.Migrations.ConvertTrialsToFreeTier do
  use Ecto.Migration

  def up do
    execute "UPDATE users SET status = 'free', trial_expires_at = NULL WHERE status = 'trial'"
    execute "UPDATE users SET status = 'free', plan_expires_at = NULL WHERE status = 'inactive'"
  end

  def down do
    # Best-effort rollback: convert free users back to inactive
    execute "UPDATE users SET status = 'inactive' WHERE status = 'free'"
  end
end
