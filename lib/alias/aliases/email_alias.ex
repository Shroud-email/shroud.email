defmodule Alias.Aliases.EmailAlias do
  use Ecto.Schema
  import Ecto.Changeset
  alias Alias.Accounts.User

  schema "email_aliases" do
    field :address, :string
    field :enabled, :boolean, default: true
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(email_alias, attrs \\ %{}) do
    email_alias
    |> cast(attrs, [:address, :enabled, :user_id])
    |> validate_required([:address, :enabled, :user_id])
    |> unique_constraint(:address)
  end
end
