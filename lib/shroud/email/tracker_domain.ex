defmodule Shroud.Email.TrackerDomain do
  @moduledoc """
  A per-day count of how often a tracking domain was blocked. Each row records
  the number of emails containing a tracking pixel from a given domain on a
  given day, letting us chart how trackers trend over time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tracker_domain_metrics" do
    field :domain, :string
    field :date, :date
    field :count, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(tracker_domain, attrs) do
    tracker_domain
    |> cast(attrs, [:domain, :date, :count])
    |> validate_required([:domain, :date, :count])
  end
end
