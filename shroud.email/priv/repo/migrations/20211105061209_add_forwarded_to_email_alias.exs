defmodule Shroud.Repo.Migrations.AddForwardedToEmailAlias do
  use Ecto.Migration

  def change do
    alter table(:email_aliases) do
      add :forwarded, :integer, default: 0, null: false
    end
  end
end
