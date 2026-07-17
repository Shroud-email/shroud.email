defmodule ShroudWeb.CustomDomainLive.IndexTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Index" do
    setup :register_and_log_in_user

    test "shows the empty state when the user has no domains", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/domains")

      refute has_element?(view, "#domains")
      assert has_element?(view, "button", "Add domain")
    end
  end
end
