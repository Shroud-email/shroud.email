defmodule Shroud.Accounts.PasskeyCredential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "passkey_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :label, :string
    belongs_to :user, Shroud.Accounts.User
    timestamps()
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:credential_id, :public_key, :label, :sign_count])
    |> validate_required([:user_id, :credential_id, :public_key, :sign_count])
    |> validate_length(:label, max: 100)
    |> validate_number(:sign_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:credential_id)
  end
end
