defmodule Shroud.Repo.Migrations.AddDomainForeignKeyToAliases do
  use Ecto.Migration

  def up do
    drop constraint(:spam_emails, "spam_emails_email_alias_id_fkey")

    alter table(:email_aliases) do
      add :domain_id, references(:custom_domains, on_delete: :delete_all)
    end

    alter table(:spam_emails) do
      modify :email_alias_id, references(:email_aliases, on_delete: :delete_all)
    end
  end

  def down do
    drop constraint(:spam_emails, "spam_emails_email_alias_id_fkey")

    alter table(:email_aliases) do
      remove :domain_id
    end

    alter table(:spam_emails) do
      modify :email_alias_id, references(:email_aliases)
    end
  end
end
