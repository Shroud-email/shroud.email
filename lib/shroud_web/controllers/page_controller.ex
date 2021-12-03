defmodule ShroudWeb.PageController do
  use ShroudWeb, :controller
  alias Shroud.Util

  def email_report(conn, %{"data" => b64_data}) do
    case Util.uri_decode_map(b64_data) do
      {:ok, decoded} ->
        render(
          conn,
          "email_report.html",
          trackers: decoded["trackers"],
          sender: decoded["sender"],
          email_alias: decoded["email_alias"],
          layout: {ShroudWeb.LayoutView, "report.html"}
        )

      :error ->
        conn
        |> put_status(:not_found)
        |> put_view(ShroudWeb.ErrorView)
        |> render(:"404")
    end
  end
end
