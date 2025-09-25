defmodule Shroud.Accounts.LoopsJobTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Accounts.LoopsJob
  import Shroud.AccountsFixtures

  setup :verify_on_exit!

  describe "perform/1" do
    test "sends a request to the Loops API" do
      user = user_fixture()
      event_name = "user_signed_up"
      event_properties = %{"source" => "web"}
      mailing_lists = %{"newsletter" => true}

      Shroud.MockHTTPoison
      |> expect(:post, fn url, payload, headers ->
        assert url == "https://app.loops.so/api/v1/events/send"

        assert Jason.decode!(payload) == %{
                 "email" => user.email,
                 "eventName" => event_name,
                 "eventProperties" => event_properties,
                 "mailingLists" => mailing_lists
               }

        assert headers == [
                 "Content-Type": "application/json",
                 Authorization: "Bearer secret"
               ]

        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      perform_job(LoopsJob, %{
        user_id: user.id,
        event_name: event_name,
        event_properties: event_properties,
        mailing_lists: mailing_lists
      })
    end

    test "does nothing if API key not configured" do
      user = user_fixture()
      expect(Shroud.MockHTTPoison, :post, 0, fn _url, _payload, _headers -> :ok end)

      Application.delete_env(:shroud, :loops_api_key)
      on_exit(fn -> Application.put_env(:shroud, :loops_api_key, "secret") end)

      perform_job(LoopsJob, %{
        user_id: user.id,
        event_name: "user_signed_up",
        event_properties: %{},
        mailing_lists: %{}
      })
    end
  end
end
