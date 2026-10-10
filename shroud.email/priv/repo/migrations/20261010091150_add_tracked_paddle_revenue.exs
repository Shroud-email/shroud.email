defmodule Shroud.Repo.Migrations.AddTrackedPaddleRevenue do
  use Ecto.Migration

  def change do
    create table(:tracked_paddle_revenue, primary_key: false) do
      add :transaction_id, :string, primary_key: true
    end
  end
end
