defmodule ShroudWeb.EmailAliasLiveTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.AliasesFixtures

  describe "Index" do
    setup :register_and_log_in_user

    setup %{user: user} do
      %{
        email_alias: alias_fixture(%{user_id: user.id})
      }
    end

    test "lists all email_aliases", %{conn: conn, email_alias: email_alias} do
      {:ok, _index_live, html} =
        conn
        |> live(Routes.email_alias_index_path(conn, :index))

      assert html =~ "Aliases"
      assert html =~ email_alias.address
    end

    test "creates new email_alias", %{conn: conn} do
      {:ok, index_live, _html} =
        conn
        |> live(Routes.email_alias_index_path(conn, :index))

      html = index_live |> element("button", "New alias") |> render_click()

      assert html =~ "Created new alias"
      assert html =~ "@shroud.local"
    end

    test "deletes email_alias in listing", %{conn: conn, email_alias: email_alias} do
      {:ok, index_live, _html} =
        conn
        |> live(Routes.email_alias_index_path(conn, :index))

      assert index_live |> element("#alias-#{email_alias.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#alias-#{email_alias.id}")
    end
  end
end
