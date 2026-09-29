defmodule Shroud.Repo.Migrations.AddSpamassassinHeaderToSpamEmails do
  use Ecto.Migration

  def change do
    alter table(:spam_emails) do
      add :spamassassin_header, :text
    end
  end
end
