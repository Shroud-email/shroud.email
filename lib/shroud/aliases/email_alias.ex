defmodule Shroud.Aliases.EmailAlias do
  use Ecto.Schema
  import Ecto.Changeset
  alias Shroud.Accounts.User

  schema "email_aliases" do
    field :address, :string
    field :enabled, :boolean, default: true
    field :forwarded, :integer, default: 0
    field :deleted_at, :naive_datetime
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(email_alias, attrs \\ %{}) do
    email_alias
    |> cast(attrs, [:address, :enabled, :forwarded, :user_id, :deleted_at])
    |> validate_required([:address, :enabled, :user_id])
    |> unique_constraint(:address)
  end
end
