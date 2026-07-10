defmodule Shroud.Repo.Migrations.RenameStripeToPaddleFields do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :paddle_customer_id, :string
      add :paddle_subscription_id, :string
      add :last_paddle_event_at, :naive_datetime
    end
  end

  def down do
    alter table(:users) do
      remove :last_paddle_event_at
      remove :paddle_subscription_id
      remove :paddle_customer_id
    end
  end
end
