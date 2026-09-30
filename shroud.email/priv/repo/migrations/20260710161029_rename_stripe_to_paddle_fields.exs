defmodule Shroud.Repo.Migrations.RenameStripeToPaddleFields do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :paddle_customer_id, :string
      add :paddle_subscription_id, :string
      add :paddle_price_id, :string
      add :paddle_checkout_transaction_id, :string
      add :paddle_checkout_price_id, :string
      add :last_paddle_event_at, :naive_datetime_usec
    end

    create unique_index(:users, [:paddle_customer_id])
  end

  def down do
    drop unique_index(:users, [:paddle_customer_id])

    alter table(:users) do
      remove :last_paddle_event_at
      remove :paddle_checkout_price_id
      remove :paddle_checkout_transaction_id
      remove :paddle_price_id
      remove :paddle_subscription_id
      remove :paddle_customer_id
    end
  end
end
