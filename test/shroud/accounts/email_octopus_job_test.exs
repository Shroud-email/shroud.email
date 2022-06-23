defmodule Shroud.Accounts.EmailOctopusJobTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Accounts.EmailOctopusJob
  import Shroud.AccountsFixtures

  setup :verify_on_exit!

  describe "perform/1" do
    test "sends a request to the EmailOctopus API" do
      user = user_fixture()

      Shroud.MockHTTPoison
      |> expect(:post, fn url, payload, headers ->
        assert url == "https://emailoctopus.com/api/1.6/lists/123/contacts"

        assert Jason.decode!(payload) == %{
                 "api_key" => "deadbeef",
                 "email_address" => user.email,
                 "status" => "SUBSCRIBED"
               }

        assert headers == ["Content-Type": "application/json"]
        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      perform_job(EmailOctopusJob, %{user_id: user.id})
    end

    test "does nothing if API key not configured" do
      user = user_fixture()
      expect(Shroud.MockHTTPoison, :post, 0, fn _url, _payload, _headers -> :ok end)

      Application.delete_env(:shroud, :email_octopus_api_key)
      on_exit(fn -> Application.put_env(:shroud, :email_octopus_api_key, "123") end)
      perform_job(EmailOctopusJob, %{user_id: user.id})
    end

    test "does nothing if list ID not configured" do
      user = user_fixture()
      expect(Shroud.MockHTTPoison, :post, 0, fn _url, _payload, _headers -> :ok end)

      Application.delete_env(:shroud, :email_octopus_list_id)
      on_exit(fn -> Application.put_env(:shroud, :email_octopus_list_id, "123") end)
      perform_job(EmailOctopusJob, %{user_id: user.id})
    end
  end
end
