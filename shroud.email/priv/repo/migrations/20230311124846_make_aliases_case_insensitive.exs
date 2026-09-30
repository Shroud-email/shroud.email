defmodule Shroud.Repo.Migrations.MakeAliasesCaseInsensitive do
  use Ecto.Migration

  def change do
    alter table(:email_aliases) do
      modify :address, :citext
    end
  end
end
