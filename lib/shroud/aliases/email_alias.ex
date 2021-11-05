defmodule Shroud.Aliases.EmailAlias do
  use Ecto.Schema
  import Ecto.Changeset
  alias Shroud.Accounts.User
  alias Shroud.Aliases.EmailMetric

  schema "email_aliases" do
    field :address, :string
    field :enabled, :boolean, default: true
    field :forwarded, :integer, default: 0
    has_many :metrics, EmailMetric, foreign_key: :alias_id
    field :deleted_at, :naive_datetime
    field :forwarded_in_last_30_days, :integer, virtual: true, default: 0
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
