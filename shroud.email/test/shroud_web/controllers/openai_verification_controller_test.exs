defmodule ShroudWeb.OpenaiVerificationControllerTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint ShroudWeb.Endpoint

  test "domain verification returns the exact public challenge as plain text" do
    conn = build_conn() |> get("/.well-known/openai-apps-challenge")

    assert response(conn, 200) == "slWSuM4f2hah-C8mTjIgiQoGp8MNH7HYR-Vq0VPaaAk"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(conn, "location") == []
  end
end
