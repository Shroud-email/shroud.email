defmodule Shroud.Accounts.LoopsJobTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Accounts.LoopsJob
  import Shroud.AccountsFixtures

  setup :verify_on_exit!

  describe "perform/1" do
    setup do
      Application.put_env(:shroud, :loops_api_key, "secret")
      :ok
    end

    test "sends a request to the Loops API" do
      user = user_fixture(%{status: :active})
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
                 "mailingLists" => mailing_lists,
                 "status" => "active"
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

    test "syncs the latest non-lead contact properties" do
      user = user_fixture(%{status: :free})

      Shroud.MockHTTPoison
      |> expect(:put, fn url, payload, headers, [] ->
        assert url == "https://app.loops.so/api/v1/contacts/update"

        assert Jason.decode!(payload) == %{
                 "email" => user.email,
                 "status" => "free"
               }

        assert headers == [
                 "Content-Type": "application/json",
                 Authorization: "Bearer secret"
               ]

        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      assert :ok = perform_job(LoopsJob, %{action: "sync_loops", user_id: user.id})
    end

    test "does not sync lead contacts" do
      user = user_fixture(%{status: :lead})
      expect(Shroud.MockHTTPoison, :put, 0, fn _, _, _, _ -> :ok end)

      assert :ok = perform_job(LoopsJob, %{action: "sync_loops", user_id: user.id})
    end

    test "returns an error for a failed Loops response" do
      user = user_fixture(%{status: :active})

      Shroud.MockHTTPoison
      |> expect(:put, fn _, _, _, [] ->
        {:ok, %HTTPoison.Response{status_code: 500, body: "unavailable"}}
      end)

      assert {:error, {:loops_api, 500, "unavailable"}} =
               perform_job(LoopsJob, %{action: "sync_loops", user_id: user.id})
    end

    test "accepts an existing string status property" do
      expect_properties([%{"key" => "status", "label" => "Status", "type" => "string"}])

      assert :ok = LoopsJob.ensure_contact_properties()
    end

    test "creates a missing status property" do
      expect_properties([])

      expect(Shroud.MockHTTPoison, :post, fn url, payload, _headers ->
        assert url == "https://app.loops.so/api/v1/contacts/properties"
        assert Jason.decode!(payload) == %{"name" => "status", "type" => "string"}
        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      assert :ok = LoopsJob.ensure_contact_properties()
    end

    test "rejects a status property with the wrong type" do
      expect_properties([%{"key" => "status", "label" => "Status", "type" => "boolean"}])

      assert {:error, {:invalid_contact_property_type, "status", "boolean"}} =
               LoopsJob.ensure_contact_properties()
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

  defp expect_properties(properties) do
    expect(Shroud.MockHTTPoison, :get, fn url, _headers, [] ->
      assert url == "https://app.loops.so/api/v1/contacts/properties?list=custom"
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(properties)}}
    end)
  end
end
