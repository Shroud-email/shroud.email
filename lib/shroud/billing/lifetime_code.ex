defmodule Shroud.Billing.LifetimeCode do
  use Ecto.Schema
  import Ecto.Changeset
  alias Shroud.Accounts.User

  schema "lifetime_codes" do
    field :code, :string
    belongs_to :redeemed_by, User

    timestamps()
  end

  @doc false
  def changeset(lifetime_code, attrs) do
    lifetime_code
    |> cast(attrs, [:code, :redeemed_by_id])
    |> validate_required([:code, :redeemed_by_id])
    |> unique_constraint(:code)
  end
end
