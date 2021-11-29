defmodule Shroud.EmailTest do
  use Shroud.DataCase, async: true
  alias Shroud.Repo
  alias Shroud.Email
  alias Shroud.Email.Tracker

  setup do
    changeset = Tracker.changeset(%Tracker{}, %{name: "Tracker Co.", pattern: "tracker\.co"})
    tracker = Repo.insert!(changeset)
    %{tracker: tracker}
  end

  describe "list_trackers/0" do
    test "fetches all trackers", %{tracker: tracker} do
      trackers = Email.list_trackers()

      assert length(trackers) == 1
      assert hd(trackers).name == tracker.name
      assert hd(trackers).pattern == tracker.pattern
    end
  end
end
