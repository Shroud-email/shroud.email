defmodule Shroud.Repo.Migrations.AddPaidConvertedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :paid_converted_at, :utc_datetime_usec
    end
  end
end
