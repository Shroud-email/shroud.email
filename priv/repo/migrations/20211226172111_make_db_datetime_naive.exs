defmodule Shroud.Repo.Migrations.MakeDbDatetimeNaive do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :trial_expires_at
      add :trial_expires_at, :naive_datetime

      remove :plan_expires_at
      add :plan_expires_at, :naive_datetime
    end
  end
end
