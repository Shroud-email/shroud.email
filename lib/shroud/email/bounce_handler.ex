defmodule Shroud.Email.BounceHandler do
  @moduledoc """
  Handles various kinds of bounces.
  """
  require Logger
  alias Shroud.S3.S3UploadJob

  @doc """
  Handles a bounce report from Haraka. These are sent when Haraka
  attempts to deliver a message, but fails, e.g. because of a 554
  "transaction failed".

  This might happen if e.g. the MTA's IP is on a blocklist, so the
  recipient refuses to accept the message.
  """
  @spec handle_haraka_bounce_report(String.t(), String.t()) :: :ok
  def handle_haraka_bounce_report(to, data) do
    s3_path = "/bounces/#{to}-#{date_time().utc_now_unix()}.eml"

    %{path: s3_path, contents: data}
    |> S3UploadJob.new()
    |> Oban.insert!()

    Logger.warn("Received bounce report from Haraka! See #{s3_path}.")
    :ok
  end

  defp date_time do
    Application.get_env(:shroud, :datetime_module, Shroud.DateTime)
  end
end
