defmodule ShroudWeb.ConnectionController do
  use ShroudWeb, :controller
  alias Shroud.Mcp

  plug :private_page

  def index(conn, _params) do
    render(conn, :index,
      connections: Mcp.list_connections(conn.assigns.current_user),
      page_title: "Connected apps"
    )
  end

  def delete(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {id, ""} -> Mcp.revoke(conn.assigns.current_user, id)
      _ -> :error
    end

    redirect(conn, to: ~p"/settings/connections")
  end

  defp private_page(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end
end
