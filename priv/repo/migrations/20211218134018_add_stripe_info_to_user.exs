defmodule Shroud.Repo.Migrations.AddStripeInfoToUser do
  use Ecto.Migration

  def change do
    create_query = "CREATE TYPE user_status AS ENUM ('lead', 'trial', 'active', 'inactive')"
    drop_query = "DROP TYPE user_status"
    execute(create_query, drop_query)

    alter table(:users) do
      add :stripe_customer_id, :string
      add :trial_expires_at, :utc_datetime
      add :plan_expires_at, :utc_datetime
      add :status, :user_status, default: "lead"
    end
  end
end
