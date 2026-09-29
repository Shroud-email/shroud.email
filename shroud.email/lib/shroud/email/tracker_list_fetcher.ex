defmodule Shroud.Email.TrackerListFetcher do
  # Unique across all fields and states for one hour
  use Oban.Worker, queue: :default, unique: [period: 3600]

  import Ecto.Query
  alias Shroud.{Email, Repo}
  alias Shroud.Email.Tracker

  @list_uri Application.compile_env!(:shroud, :tracker_list_uri)

  @impl Oban.Worker
  def perform(_job) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %{body: response_body} = http().get!(@list_uri)

    current_trackers = Email.list_trackers() |> MapSet.new()

    new_trackers =
      response_body
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(fn string -> string !== "" end)
      |> Enum.map(&String.split(&1, "@@="))
      |> Enum.map(fn [name, pattern] -> %{name: name, pattern: pattern} end)
      |> MapSet.new()

    deleted_patterns =
      MapSet.difference(current_trackers, new_trackers) |> Enum.map(&Map.get(&1, :pattern))

    from(t in Tracker, where: t.pattern in ^deleted_patterns) |> Repo.delete_all()

    added_trackers =
      MapSet.difference(new_trackers, current_trackers)
      |> Enum.map(fn struct ->
        struct
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Tracker, added_trackers,
      on_conflict: :nothing,
      conflict_target: [:name, :pattern]
    )

    :ok
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
