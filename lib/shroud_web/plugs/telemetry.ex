defmodule ShroudWeb.Plug.Telemetry do
  @moduledoc """
  Like Plug.Telemetry, but sets the log level to :debug
  on the _health endpoint (as opposed to :info).

  See also https://stackoverflow.com/a/57587646/3697202.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: Plug.Telemetry.init(opts)

  @impl true
  def call(%{path_info: ["_health"]} = conn, {start_event, stop_event, opts}) do
    Plug.Telemetry.call(conn, {start_event, stop_event, Keyword.put(opts, :log, :debug)})
  end

  def call(conn, args), do: Plug.Telemetry.call(conn, args)
end
