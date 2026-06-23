defmodule ShroudWeb.CustomDomainLive.IndexStreamTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.DomainFixtures

  describe "Index" do
    setup :register_and_log_in_user

    test "shows the empty state when the user has no domains", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/domains")

      refute has_element?(view, "#domains")
      assert has_element?(view, "button", "Add domain")
    end

    test "renders the user's domains in the stream container", %{conn: conn, user: user} do
      domain = custom_domain_fixture(%{user_id: user.id})

      {:ok, view, _html} = live(conn, ~p"/domains")

      assert has_element?(view, "#domains[phx-update=stream]")
      assert has_element?(view, "#domains a", domain.domain)
    end
  end
end
