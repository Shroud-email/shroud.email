defmodule ShroudWeb.Plug.Telemetry do
  @moduledoc """
  Uses debug logging for health checks and suppresses request logging for
  unsubscribe URLs containing bearer capabilities.

  See also https://stackoverflow.com/a/57587646/3697202.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: Plug.Telemetry.init(opts)

  @impl true
  def call(%{path_info: ["_health"]} = conn, {start_event, stop_event, opts}) do
    Plug.Telemetry.call(conn, {start_event, stop_event, Keyword.put(opts, :log, :debug)})
  end

  def call(%{path_info: ["unsubscribe", _token]} = conn, {start_event, stop_event, opts}) do
    Plug.Telemetry.call(conn, {start_event, stop_event, Keyword.put(opts, :log, false)})
  end

  def call(conn, args), do: Plug.Telemetry.call(conn, args)
end
