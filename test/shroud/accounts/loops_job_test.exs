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

      Shroud.MockHTTPoison
      |> expect(:post, fn url, payload, headers ->
        assert url == "https://app.loops.so/api/v1/contacts/create"

        assert Jason.decode!(payload) == %{
                 "email" => user.email,
                 "newsletterId" => "loops_newsletter"
               }

        assert headers == [
                 "Content-Type": "application/json",
                 Authorization: "Bearer secret"
               ]

        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      perform_job(LoopsJob, %{user_id: user.id})
    end

    test "does nothing if API key not configured" do
      user = user_fixture()
      expect(Shroud.MockHTTPoison, :post, 0, fn _url, _payload, _headers -> :ok end)

      Application.delete_env(:shroud, :loops_api_key)
      on_exit(fn -> Application.put_env(:shroud, :loops_api_key, "secret") end)
      perform_job(LoopsJob, %{user_id: user.id})
    end

    test "does nothing if newsletter ID not configured" do
      user = user_fixture()
      expect(Shroud.MockHTTPoison, :post, 0, fn _url, _payload, _headers -> :ok end)

      Application.delete_env(:shroud, :loops_newsletter_id)
      on_exit(fn -> Application.put_env(:shroud, :loops_newsletter_id, "loops_newsletter") end)
      perform_job(LoopsJob, %{user_id: user.id})
    end
  end
end
