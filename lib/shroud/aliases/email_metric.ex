defmodule Shroud.Aliases.EmailMetric do
  use Ecto.Schema
  import Ecto.Changeset
  alias Shroud.Aliases.EmailAlias

  schema "email_metrics" do
    field :date, :date
    field :forwarded, :integer, default: 0
    field :blocked, :integer, default: 0
    belongs_to :alias, EmailAlias

    timestamps()
  end

  @doc false
  def changeset(email_metric, attrs) do
    email_metric
    |> cast(attrs, [:alias_id, :date, :forwarded, :blocked])
    |> validate_required([:alias_id, :date, :forwarded, :blocked])
  end
end
