defmodule ShroudWeb.PageControllerTest do
  use ShroudWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert redirected_to(conn, 302) == "/users/log_in"
  end
end
