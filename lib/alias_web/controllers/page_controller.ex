defmodule AliasWeb.PageController do
  use AliasWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
