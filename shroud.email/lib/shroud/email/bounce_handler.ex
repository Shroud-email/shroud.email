defmodule Shroud.Email.BounceHandler do
  @moduledoc """
  Handles various kinds of bounces.
  """
  require Logger

  @doc """
  Reports an unclassified null-envelope-sender message to Sentry.
  Reports share one issue and contain no email data or delivery identifiers.
  """
  @spec handle_haraka_bounce_report(String.t(), String.t()) :: :ok
  def handle_haraka_bounce_report(_to, _data) do
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
      fingerprint: event.fingerprint
    }
    |> Sentry.send_event()

    Logger.warning("Received an unclassified email bounce report")
    :ok
  end
end
