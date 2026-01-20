defmodule Shroud.Email.FailedEmailExporter do
  @moduledoc """
  Exports emails from errored Oban jobs as .eml files.
  """

  import Ecto.Query

  alias Shroud.Repo

  @doc """
  Lists failed EmailHandler jobs.

  ## Options
    * `:limit` - Maximum number of jobs to return (default: no limit)
  """
  @spec list_failed_jobs(keyword()) :: [Oban.Job.t()]
  def list_failed_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit)

    query =
      from j in Oban.Job,
        where: j.worker == ^"Shroud.Email.EmailHandler" and fragment("? != '{}'", j.errors)

    query =
      if limit do
        from j in query, limit: ^limit
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Exports a single job's email data to a .eml file.

  Returns the path to the created file.
  """
  @spec export_job(Oban.Job.t(), Path.t()) :: Path.t()
  def export_job(%Oban.Job{} = job, output_dir) do
    File.mkdir_p!(output_dir)

    data = decode_data(job.args["data"])
    filename = build_filename(job)
    path = Path.join(output_dir, filename)

    File.write!(path, data)

    path
  end

  @doc """
  Exports all failed EmailHandler jobs as .eml files.

  ## Options
    * `:output_dir` - Directory to write files to (required)
    * `:limit` - Maximum number of jobs to export (default: no limit)

  Returns a list of paths to the created files.
  """
  @spec export_failed_jobs(keyword()) :: [Path.t()]
  def export_failed_jobs(opts) do
    output_dir = Keyword.fetch!(opts, :output_dir)
    limit = Keyword.get(opts, :limit)

    list_opts = if limit, do: [limit: limit], else: []

    list_failed_jobs(list_opts)
    |> Enum.map(&export_job(&1, output_dir))
  end

  defp decode_data(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  defp build_filename(%Oban.Job{} = job) do
    from = sanitize_filename_component(job.args["from"] || "unknown")
    to = sanitize_filename_component(job.args["to"])

    "#{job.id}_#{from}_to_#{to}.eml"
  end

  defp sanitize_filename_component(value) when is_list(value) do
    value
    |> Enum.join(",")
    |> sanitize_filename_component()
  end

  defp sanitize_filename_component(value) when is_binary(value) do
    value
    |> String.replace(~r/[^\w@.-]/, "_")
    |> String.slice(0, 50)
  end

  defp sanitize_filename_component(_), do: "unknown"
end
