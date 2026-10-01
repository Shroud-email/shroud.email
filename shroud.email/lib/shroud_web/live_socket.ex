defmodule ShroudWeb.LiveSocket do
  @moduledoc "Checks the HTTP allowance before upgrading a LiveView connection."
  use Phoenix.LiveView.Socket
  alias Phoenix.Transports.WebSocket
  alias ShroudWeb.Plugs.{ClientIP, RateLimit}

  @impl true
  defdelegate id(socket), to: Phoenix.LiveView.Socket

  @impl true
  def connect(_params, socket, %{peer_data: %{address: peer}} = info) do
    ip = ClientIP.resolve(peer, info[:x_headers] || [])

    case Shroud.RateLimit.check(:http, {:ip, ip}) do
      {:allow, _} -> {:ok, socket}
      result -> {:error, {:rate_limit, result}}
    end
  end

  def handle_error(conn, {:rate_limit, result}),
    do: RateLimit.respond(conn, result)

  def handle_error(conn, reason),
    do: WebSocket.handle_error(conn, reason)
end
