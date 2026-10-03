defmodule Shroud.ErrorReporter do
  def before_send(%Sentry.Event{
        original_exception: %Plug.CSRFProtection.InvalidCSRFTokenError{}
      }),
      do: nil

  def before_send(event), do: event

  def handle_event([:oban, :job, :exception], measure, meta, _) do
    extra =
      meta.job
      |> Map.take([:id, :args, :meta, :queue, :worker])
      |> Map.merge(measure)

    Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace, extra: extra)
  end
end
