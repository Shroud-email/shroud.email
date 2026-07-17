defmodule ShroudWeb.CustomDomainLive.ShowTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.DomainFixtures

  alias Shroud.Domain

  describe "Show" do
    setup :register_and_log_in_user

    setup %{user: user} do
      %{
        domain: custom_domain_fixture(%{user_id: user.id})
      }
    end

    test "renders the domain", %{conn: conn, domain: domain} do
      {:ok, _view, html} = live(conn, ~p"/domains/#{domain.domain}")

      assert html =~ domain.domain
    end

    test "deletes the domain", %{conn: conn, user: user, domain: domain} do
      {:ok, view, _html} = live(conn, ~p"/domains/#{domain.domain}")

      view
      |> element("form[phx-submit='delete']")
      |> render_submit()

      assert_redirect(view, ~p"/domains")

      assert_raise Ecto.NoResultsError, fn ->
        Domain.get_custom_domain!(user, domain.domain)
      end
    end
  end
end
