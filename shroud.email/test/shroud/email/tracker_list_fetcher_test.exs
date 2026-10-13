defmodule Shroud.Email.TrackerListFetcherTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Email.TrackerListFetcher
  alias Shroud.Email

  setup :verify_on_exit!

  describe "perform/1" do
    test "saves all trackers" do
      Shroud.MockHTTPoison
      |> expect(:get!, fn _ ->
        body = """
        Tracker Co.@@=tracker\.co
        Another@@=reg(ex)?\/pattern.*
        """

        %HTTPoison.Response{body: body, status_code: 200}
      end)

      perform_job(TrackerListFetcher, %{})

      trackers = Email.list_trackers()
      assert length(trackers) == 2
      assert Enum.any?(trackers, &match?(%{name: "Tracker Co.", pattern: "tracker\.co"}, &1))
      assert Enum.any?(trackers, &match?(%{name: "Another", pattern: "reg(ex)?\/pattern.*"}, &1))
    end

    test "adds new trackers" do
      Shroud.MockHTTPoison
      |> expect(:get!, 1, fn _ ->
        body = """
        Tracker Co.@@=tracker\.co
        """

        %HTTPoison.Response{body: body, status_code: 200}
      end)
      |> expect(:get!, 1, fn _ ->
        body = """
        Tracker Co.@@=tracker\.co
        Another@@=reg(ex)?\/pattern.*
        """

        %HTTPoison.Response{body: body, status_code: 200}
      end)

      perform_job(TrackerListFetcher, %{})
      trackers = Email.list_trackers()
      assert length(trackers) == 1
      perform_job(TrackerListFetcher, %{})

      trackers = Email.list_trackers()
      assert length(trackers) == 2
      assert Enum.any?(trackers, &match?(%{name: "Tracker Co.", pattern: "tracker\.co"}, &1))
      assert Enum.any?(trackers, &match?(%{name: "Another", pattern: "reg(ex)?\/pattern.*"}, &1))
    end

    test "retains unchanged rows when refreshing or removing a tracker with the same pattern" do
      {:ok, kept} = Email.create_tracker(%{name: "Kept", pattern: "shared"})
      {:ok, removed} = Email.create_tracker(%{name: "Removed", pattern: "shared"})

      Shroud.MockHTTPoison
      |> expect(:get!, 2, fn _ ->
        %HTTPoison.Response{body: "Kept@@=shared\n", status_code: 200}
      end)

      assert :ok = perform_job(TrackerListFetcher, %{})
      assert Repo.reload(kept) == kept
      assert Repo.reload(removed) == nil

      assert :ok = perform_job(TrackerListFetcher, %{})
      assert Repo.reload(kept) == kept
      assert [%Shroud.Email.Tracker{name: "Kept", pattern: "shared"}] = Email.list_trackers()
    end

    test "deletes removed trackers" do
      Shroud.MockHTTPoison
      |> expect(:get!, 1, fn _ ->
        body = """
        Tracker Co.@@=tracker\.co
        Another@@=reg(ex)?\/pattern.*
        """

        %HTTPoison.Response{body: body, status_code: 200}
      end)
      |> expect(:get!, 1, fn _ ->
        body = """
        Tracker Co.@@=tracker\.co
        """

        %HTTPoison.Response{body: body, status_code: 200}
      end)

      perform_job(TrackerListFetcher, %{})
      trackers = Email.list_trackers()
      assert length(trackers) == 2
      perform_job(TrackerListFetcher, %{})

      trackers = Email.list_trackers()
      assert length(trackers) == 1
      assert Enum.any?(trackers, &match?(%{name: "Tracker Co.", pattern: "tracker\.co"}, &1))
      refute Enum.any?(trackers, &match?(%{name: "Another", pattern: "reg(ex)?\/pattern.*"}, &1))
    end
  end
end
