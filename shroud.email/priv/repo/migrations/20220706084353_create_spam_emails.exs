defmodule Shroud.Repo.Migrations.CreateSpamEmails do
  use Ecto.Migration

  def change do
    create table(:spam_emails) do
      add :from, :text, null: false
      add :subject, :text
      add :html_body, :text
      add :text_body, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :email_alias_id, references(:email_aliases, on_delete: :nothing), null: false

      timestamps()
    end

    create index(:spam_emails, [:user_id])
    create index(:spam_emails, [:email_alias_id])
  end
end
