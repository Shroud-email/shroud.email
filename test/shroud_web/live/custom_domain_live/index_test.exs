defmodule ShroudWeb.CustomDomainLive.IndexTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.DomainFixtures

  describe "Index" do
    setup :register_and_log_in_user

    test "renders an SVG indicator (not a bare <icon> tag) for unverified domains",
         %{conn: conn, user: user} do
      _domain =
        custom_domain_fixture(%{user_id: user.id, domain: "unverified.com", mx_verified_at: nil})

      {:ok, _index_live, html} = live(conn, ~p"/domains")

      assert html =~ "unverified.com"
      # The waiting indicator must render as a real heroicon SVG, not a literal
      # unknown <icon> element (the previous bug).
      assert html =~ "animate-pulse"
      assert html =~ ~s(<svg)
      refute html =~ ~s(<icon)
    end
  end
end
