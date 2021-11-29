defmodule Shroud.Email.TrackerListFetcherTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Email.TrackerListFetcher
  alias Shroud.Email

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
