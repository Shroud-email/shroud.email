defmodule ShroudWeb.PageController do
  use ShroudWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def not_confirmed(conn, _params) do
    render(conn, "not_confirmed.html")
  end
end
