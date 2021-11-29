defmodule Shroud.Email do
  import Ecto.Query

  alias Shroud.Repo
  alias Shroud.Email.Tracker

  def list_trackers() do
    query =
      from t in Tracker,
        select: %Tracker{name: t.name, pattern: t.pattern}

    Repo.all(query)
  end

  def create_tracker(attrs) do
    %Tracker{}
    |> Tracker.changeset(attrs)
    |> Repo.insert()
  end
end
