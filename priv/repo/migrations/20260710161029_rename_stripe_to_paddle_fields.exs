defmodule Shroud.Repo.Migrations.RenameStripeToPaddleFields do
  use Ecto.Migration

  def up do
    rename table(:users), :stripe_customer_id, to: :paddle_customer_id

    alter table(:users) do
      add :paddle_subscription_id, :string
      add :last_paddle_event_at, :naive_datetime
    end
  end

  def down do
    alter table(:users) do
      remove :last_paddle_event_at
      remove :paddle_subscription_id
    end

    rename table(:users), :paddle_customer_id, to: :stripe_customer_id
  end
end
