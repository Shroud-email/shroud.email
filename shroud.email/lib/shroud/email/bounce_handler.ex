defmodule Shroud.Email.BounceHandler do
  @moduledoc """
  Handles various kinds of bounces.
  """
  require Logger
  alias Shroud.S3.S3UploadJob

  @doc """
  Archives a bounce report and notifies Sentry with its S3 object path.
  """
  @spec handle_haraka_bounce_report(String.t(), String.t()) :: :ok
  def handle_haraka_bounce_report(to, data) do
    s3_path = "/bounces/#{to}-#{date_time().utc_now_unix()}.eml"

    %{path: s3_path, content: data}
    |> S3UploadJob.new()
    |> Oban.insert!()

    event =
      Sentry.Event.create_event(
        message: "Received an unclassified email bounce report",
        level: :warning,
        fingerprint: ["shroud-unclassified-email-bounce"]
      )

    # Allow only operational fields; inherited context can contain email data.
    %Sentry.Event{
      event_id: event.event_id,
      timestamp: event.timestamp,
      environment: event.environment,
      release: event.release,
      message: event.message,
      level: event.level,
      fingerprint: event.fingerprint,
      extra: %{s3_path: s3_path}
    }
    |> Sentry.send_event()

    Logger.warning("Received bounce report from Haraka! See #{s3_path}.")
    :ok
  end

  defp date_time do
    Application.get_env(:shroud, :datetime_module, Shroud.DateTime)
  end
end
