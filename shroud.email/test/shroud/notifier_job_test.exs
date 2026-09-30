defmodule Shroud.NotifierJobTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.NotifierJob

  setup :verify_on_exit!

  describe "perform/1" do
    test "sends a webhook with the content field" do
      Shroud.MockHTTPoison
      |> expect(:post, fn _url, payload, headers ->
        assert payload == "{\"content\":\"Lorem ipsum!\"}"
        assert headers == ["Content-Type": "application/json"]
        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      perform_job(NotifierJob, %{payload: %{content: "Lorem ipsum!"}})
    end
  end
end
