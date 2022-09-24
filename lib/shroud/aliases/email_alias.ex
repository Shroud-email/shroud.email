defmodule Shroud.Aliases.EmailAlias do
  use Ecto.Schema
  import Ecto.Changeset
  alias Shroud.Accounts.User
  alias Shroud.Aliases.EmailMetric

  schema "email_aliases" do
    field :address, :string
    field :enabled, :boolean, default: true
    field :title, :string
    field :notes, :string
    field :forwarded, :integer, default: 0
    field :blocked, :integer, default: 0
    field :replied, :integer, default: 0
    field :forwarded_in_last_30_days, :integer, virtual: true, default: 0
    field :blocked_in_last_30_days, :integer, virtual: true, default: 0
    field :replied_in_last_30_days, :integer, virtual: true, default: 0
    field :deleted_at, :naive_datetime
    field :blocked_addresses, {:array, :string}, default: []

    belongs_to :user, User
    has_many :metrics, EmailMetric, foreign_key: :alias_id

    timestamps()
  end

  # TODO: validate no underscore in local part
  @doc false
  def changeset(email_alias, attrs \\ %{}) do
    email_alias
    |> cast(attrs, [
      :address,
      :enabled,
      :title,
      :notes,
      :forwarded,
      :replied,
      :user_id,
      :deleted_at,
      :blocked_addresses
    ])
    |> validate_required([:address, :enabled, :user_id])
    |> validate_format(:address, ~r/^[^\s]+@[^\s]+$/, message: "must have an @ sign and no spaces")
    |> unique_constraint(:address)
    |> validate_blocked_addresses()
  end

  def blocked_addresses_changeset(email_alias, attrs) do
    email_alias
    |> cast(attrs, [:blocked_addresses])
    |> validate_required([:blocked_addresses])
    |> validate_blocked_addresses()
  end

  defp validate_blocked_addresses(changeset) do
    validate_change(changeset, :blocked_addresses, fn :blocked_addresses, blocked_addresses ->
      blocked_addresses
      |> Enum.map(&validate_blocked_address/1)
      |> Enum.reject(&is_nil/1)
      |> Keyword.new()
    end)
  end

  defp validate_blocked_address(address) do
    cond do
      not Regex.match?(~r/^[^\s]+@[^\s]+$/, address) ->
        {:blocked_addresses, "addresses must have the @ sign and no spaces"}

      String.length(address) > 160 ->
        {:blocked_addresses, "addresses cannot be greater than 160 characters"}

      true ->
        nil
    end
  end
end
