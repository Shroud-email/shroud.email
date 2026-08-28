defmodule Mix.Tasks.SyncLoops do
  use Mix.Task

  import Ecto.Query

  alias Shroud.Accounts
  alias Shroud.Accounts.{LoopsJob, User}
  alias Shroud.Repo

  @shortdoc "Enqueues Loops contact synchronization for all non-lead users"

  @moduledoc """
  Enqueues Loops contact synchronization for all non-lead users.

      mix sync_loops

  The task creates the Loops `status` contact property when needed and rejects
  an existing property with a conflicting type.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    ensure_contact_properties!()

    users = Repo.all(from user in User, where: user.status != :lead)

    Enum.each(users, &enqueue_sync!/1)

    Mix.shell().info("Enqueued #{length(users)} Loops sync job(s)")
  end

  defp enqueue_sync!(user) do
    case Accounts.enqueue_loops_sync(user) do
      {:ok, _job} ->
        :ok

      {:error, changeset} ->
        Mix.raise("Could not enqueue Loops sync: #{inspect(changeset.errors)}")
    end
  end

  defp ensure_contact_properties! do
    case LoopsJob.ensure_contact_properties() do
      :ok ->
        :ok

      {:error, :loops_not_configured} ->
        Mix.raise("Loops API key is not configured")

      {:error, {:invalid_contact_property_type, "status", type}} ->
        Mix.raise("Loops contact property status must be a string, got: #{type}")

      {:error, reason} ->
        Mix.raise("Could not prepare Loops contact properties: #{inspect(reason)}")
    end
  end
end
