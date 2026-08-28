defmodule Mix.Tasks.SyncLoopsTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo

  import ExUnit.CaptureIO
  import Mox
  import Shroud.AccountsFixtures

  alias Mix.Tasks.SyncLoops
  alias Shroud.Accounts.LoopsJob

  setup :verify_on_exit!

  setup do
    previous_api_key = Application.fetch_env(:shroud, :loops_api_key)
    Application.put_env(:shroud, :loops_api_key, "secret")

    on_exit(fn -> restore_env(:loops_api_key, previous_api_key) end)

    :ok
  end

  test "ensures properties and enqueues every non-lead user" do
    lead = user_fixture(%{status: :lead})
    free = user_fixture(%{status: :free})
    active = user_fixture(%{status: :active})

    expect_properties([%{"key" => "status", "label" => "Status", "type" => "string"}])

    Mix.Task.reenable("sync_loops")

    assert capture_io(fn -> SyncLoops.run([]) end) =~
             "Enqueued 2 Loops sync job(s)"

    assert_enqueued(worker: LoopsJob, args: %{action: "sync_loops", user_id: free.id})
    assert_enqueued(worker: LoopsJob, args: %{action: "sync_loops", user_id: active.id})
    refute_enqueued(worker: LoopsJob, args: %{action: "sync_loops", user_id: lead.id})
  end

  test "fails before enqueueing when Loops is not configured" do
    Application.delete_env(:shroud, :loops_api_key)
    user_fixture(%{status: :active})
    Mix.Task.reenable("sync_loops")

    assert_raise Mix.Error, ~r/Loops API key is not configured/, fn ->
      SyncLoops.run([])
    end

    refute_enqueued(worker: LoopsJob)
  end

  test "fails before enqueueing when the status property has the wrong type" do
    user_fixture(%{status: :active})
    expect_properties([%{"key" => "status", "label" => "Status", "type" => "boolean"}])
    Mix.Task.reenable("sync_loops")

    assert_raise Mix.Error, ~r/status must be a string, got: boolean/, fn ->
      SyncLoops.run([])
    end

    refute_enqueued(worker: LoopsJob)
  end

  defp expect_properties(properties) do
    expect(Shroud.MockHTTPoison, :get, fn url, _headers, [] ->
      assert url == "https://app.loops.so/api/v1/contacts/properties?list=custom"
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(properties)}}
    end)
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:shroud, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:shroud, key)
end
