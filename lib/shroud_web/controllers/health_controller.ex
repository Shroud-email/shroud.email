defmodule ShroudWeb.HealthController do
  use ShroudWeb, :controller

  def show(conn, _params) do
    text(conn, "OK")
  end

end
