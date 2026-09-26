defmodule Shroud.Accounts.PasskeyChallenge do
  use Ecto.Schema

  schema "passkey_challenges" do
    field :token, :binary
    field :bytes, :binary
    field :kind, :string
    field :issued_at, :integer
    field :expires_at, :utc_datetime_usec
    belongs_to :user, Shroud.Accounts.User
  end
end
