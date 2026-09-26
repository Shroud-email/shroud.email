defmodule Shroud.Repo.Migrations.CreatePasskeyCredentials do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :passkey_handle, :binary
    end

    execute "UPDATE users SET passkey_handle = decode(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex')",
            ""

    alter table(:users) do
      modify :passkey_handle, :binary,
        null: false,
        default:
          fragment(
            "decode(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex')"
          ),
        from: {:binary, null: true, default: nil}
    end

    create unique_index(:users, [:passkey_handle])

    create table(:passkey_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :label, :string
      timestamps()
    end

    create index(:passkey_credentials, [:user_id])
    create unique_index(:passkey_credentials, [:credential_id])
  end
end
