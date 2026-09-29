defmodule Shroud.Email.FailedEmailExporterTest do
  use Shroud.DataCase, async: false

  alias Shroud.Email.EmailHandler
  alias Shroud.Email.FailedEmailExporter
  alias Shroud.Repo

  @sample_email "Subject: Test\r\n\r\nBody content\r\n"

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "shroud_failed_emails_test_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  describe "list_failed_jobs/1" do
    test "returns only errored EmailHandler jobs" do
      # Insert an errored EmailHandler job
      {:ok, errored_job} =
        %{
          from: "sender@example.com",
          to: "recipient@example.com",
          data: Base.encode64(@sample_email)
        }
        |> EmailHandler.new()
        |> Repo.insert()

      # Mark it as errored
      errored_job
      |> Ecto.Changeset.change(errors: [%{"error" => "some error", "at" => DateTime.utc_now()}])
      |> Repo.update!()

      # Insert a non-errored EmailHandler job
      {:ok, _ok_job} =
        %{
          from: "sender2@example.com",
          to: "recipient2@example.com",
          data: Base.encode64(@sample_email)
        }
        |> EmailHandler.new()
        |> Repo.insert()

      # Insert an errored job with different worker
      {:ok, _other_worker_job} =
        Repo.insert(%Oban.Job{
          worker: "SomeOtherWorker",
          queue: "default",
          args: %{"foo" => "bar"},
          errors: [%{"error" => "boom"}],
          state: "retryable"
        })

      # Fetch failed jobs
      failed_jobs = FailedEmailExporter.list_failed_jobs()

      # Should only return the errored EmailHandler job
      assert length(failed_jobs) == 1
      assert hd(failed_jobs).id == errored_job.id
    end

    test "respects limit option" do
      # Insert 3 errored EmailHandler jobs
      for i <- 1..3 do
        {:ok, job} =
          %{
            from: "sender#{i}@example.com",
            to: "recipient#{i}@example.com",
            data: Base.encode64(@sample_email)
          }
          |> EmailHandler.new()
          |> Repo.insert()

        job
        |> Ecto.Changeset.change(errors: [%{"error" => "error #{i}"}])
        |> Repo.update!()
      end

      # Fetch with limit
      failed_jobs = FailedEmailExporter.list_failed_jobs(limit: 2)

      assert length(failed_jobs) == 2
    end
  end

  describe "export_job/2" do
    test "writes decoded email data to .eml file", %{tmp_dir: tmp_dir} do
      encoded_data = Base.encode64(@sample_email)

      {:ok, job} =
        %{from: "sender@example.com", to: "recipient@example.com", data: encoded_data}
        |> EmailHandler.new()
        |> Repo.insert()

      job
      |> Ecto.Changeset.change(errors: [%{"error" => "some error"}])
      |> Repo.update!()

      job = Repo.get!(Oban.Job, job.id)

      path = FailedEmailExporter.export_job(job, tmp_dir)

      assert File.exists?(path)
      assert String.ends_with?(path, ".eml")
      assert File.read!(path) == @sample_email
    end

    test "handles non-base64 encoded data (backwards compatibility)", %{tmp_dir: tmp_dir} do
      # Legacy jobs may have raw data that isn't base64 encoded
      raw_data = @sample_email

      {:ok, job} =
        %{from: "sender@example.com", to: "recipient@example.com", data: raw_data}
        |> EmailHandler.new()
        |> Repo.insert()

      job
      |> Ecto.Changeset.change(errors: [%{"error" => "some error"}])
      |> Repo.update!()

      job = Repo.get!(Oban.Job, job.id)

      path = FailedEmailExporter.export_job(job, tmp_dir)

      assert File.exists?(path)
      assert File.read!(path) == raw_data
    end
  end

  describe "export_failed_jobs/1" do
    test "exports all failed jobs and returns paths", %{tmp_dir: tmp_dir} do
      # Insert 2 errored EmailHandler jobs
      for i <- 1..2 do
        {:ok, job} =
          %{
            from: "sender#{i}@example.com",
            to: "recipient#{i}@example.com",
            data: Base.encode64("Email #{i}\r\n")
          }
          |> EmailHandler.new()
          |> Repo.insert()

        job
        |> Ecto.Changeset.change(errors: [%{"error" => "error #{i}"}])
        |> Repo.update!()
      end

      paths = FailedEmailExporter.export_failed_jobs(output_dir: tmp_dir)

      assert length(paths) == 2
      assert Enum.all?(paths, &File.exists?/1)
      assert Enum.all?(paths, &String.ends_with?(&1, ".eml"))
    end
  end
end
