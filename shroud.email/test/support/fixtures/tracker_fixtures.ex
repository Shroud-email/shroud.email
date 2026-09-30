defmodule Shroud.TrackerFixtures do
  alias Shroud.Email

  def unique_tracker_name, do: "tracker#{System.unique_integer()}"
  def unique_tracker_pattern, do: ".*tracker#{System.unique_integer()}.*"

  def valid_tracker_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_tracker_name(),
      pattern: unique_tracker_pattern()
    })
  end

  def tracker_fixture(attrs \\ %{}) do
    {:ok, tracker} =
      attrs
      |> valid_tracker_attributes()
      |> Email.create_tracker()

    tracker
  end
end
