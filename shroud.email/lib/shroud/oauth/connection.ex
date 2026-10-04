defmodule Shroud.OAuth.Connection do
  use Ecto.Schema

  schema "oauth_connections" do
    belongs_to :user, Shroud.Accounts.User
    field :client_id, :string
    field :client_name, :string, virtual: true
    field :resource, :string
    field :scopes, {:array, :string}
    field :code_id, Ecto.UUID
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
