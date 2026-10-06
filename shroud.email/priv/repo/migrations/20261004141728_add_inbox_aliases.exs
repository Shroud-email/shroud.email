defmodule Shroud.Repo.Migrations.AddInboxAliases do
  use Ecto.Migration

  def change do
    alter table(:email_aliases) do
      add :delivery_mode, :string, null: false, default: "forward"
      add :retention_days, :integer
    end

    create constraint(:email_aliases, :valid_delivery_mode,
             check: "delivery_mode IN ('forward', 'inbox')"
           )

    create constraint(:email_aliases, :positive_retention,
             check: "retention_days IS NULL OR retention_days > 0"
           )

    create table(:inbox_messages) do
      add :email_alias_id, references(:email_aliases, on_delete: :nilify_all)
      add :storage_key, :string, null: false
      add :delivery_id, :string, null: false
      add :sender, :text, null: false
      add :subject, :text
      add :size, :integer, null: false
      add :stored, :boolean, null: false, default: false
      add :read, :boolean, null: false, default: false
      add :spam, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:inbox_messages, [:delivery_id])
    create index(:inbox_messages, [:email_alias_id, :id])
  end
end
