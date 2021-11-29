defmodule Shroud.Email.Tracker do
  use Ecto.Schema
  import Ecto.Changeset

  schema "trackers" do
    field :name, :string
    field :pattern, :string

    timestamps()
  end

  @doc false
  def changeset(tracker, attrs) do
    tracker
    |> cast(attrs, [:name, :pattern])
    |> validate_required([:name, :pattern])
  end

  def match?(%__MODULE__{pattern: pattern}, url) do
    regex = Regex.compile!(pattern)
    String.match?(url, regex)
  end
end
