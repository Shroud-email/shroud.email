defmodule Shroud.ErrorReporter do
  # SDK failure messages can contain the GenServer call's private tool inputs.
  # A primary filter redacts them before console and Sentry handlers see them.
  def filter_mcp_logs(
        %{meta: %{mfa: {ExMCP.MessageProcessor.MethodHandlers, _function, _arity}}} = event,
        _config
      ),
      do: %{event | msg: {:string, "MCP handler failed (details redacted)"}}

  def filter_mcp_logs(_event, _config), do: :ignore

  def before_send(%Sentry.Event{
        original_exception: %Plug.CSRFProtection.InvalidCSRFTokenError{}
      }),
      do: nil

  # These requests can contain OAuth credentials and private
  # alias metadata. Do not send their request context or exception data to Sentry.
  def before_send(%Sentry.Event{request: %{url: url}} = event) when is_binary(url) do
    case URI.parse(url).path do
      "/mcp" <> _ -> nil
      "/oauth/" <> _ -> nil
      "/settings/connections" <> _ -> nil
      _ -> event
    end
  end

  def before_send(event), do: event

  def handle_event([:oban, :job, :exception], measure, meta, _) do
    extra =
      meta.job
      |> Map.take([:id, :args, :meta, :queue, :worker])
      |> Map.merge(measure)

    Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace, extra: extra)
  end
end
