defmodule Mix.Tasks.ExportFailedEmails do
  @moduledoc """
  Exports emails from errored Oban jobs as .eml files.

  ## Usage

      mix export_failed_emails [options]

  ## Options

    * `--output-dir` - Directory to write files to (default: /tmp/shroud_failed_emails_<timestamp>)
    * `--limit` - Maximum number of jobs to export (default: no limit)

  ## Examples

      mix export_failed_emails
      mix export_failed_emails --limit 10
      mix export_failed_emails --output-dir /tmp/my_exports --limit 50
  """

  use Mix.Task

  alias Shroud.Email.FailedEmailExporter

  @app :shroud

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(@app)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [output_dir: :string, limit: :integer],
        aliases: [o: :output_dir, l: :limit]
      )

    output_dir = Keyword.get(opts, :output_dir, default_output_dir())
    limit = Keyword.get(opts, :limit)

    export_opts =
      [output_dir: output_dir]
      |> maybe_add_limit(limit)

    paths = FailedEmailExporter.export_failed_jobs(export_opts)

    Mix.shell().info("Exported #{length(paths)} failed email(s) to #{output_dir}")
  end

  defp default_output_dir do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    Path.join(System.tmp_dir!(), "shroud_failed_emails_#{timestamp}")
  end

  defp maybe_add_limit(opts, nil), do: opts
  defp maybe_add_limit(opts, limit), do: Keyword.put(opts, :limit, limit)
end
