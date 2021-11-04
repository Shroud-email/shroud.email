defmodule Shroud.Aliases.EmailMetric do
  use Ecto.Schema
  import Ecto.Changeset

  schema "email_metrics" do
    field :date, :date
    field :forwarded, :integer
    field :alias_id, :id

    timestamps()
  end

  @doc false
  def changeset(email_metric, attrs) do
    email_metric
    |> cast(attrs, [:alias_id, :date, :forwarded])
    |> validate_required([:alias_id, :date, :forwarded])
  end
end
