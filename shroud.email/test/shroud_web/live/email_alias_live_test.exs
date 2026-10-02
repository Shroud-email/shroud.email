defmodule ShroudWeb.EmailAliasLiveTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.AliasesFixtures
  import Shroud.DomainFixtures

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
        |> live(~p"/")

      assert html =~ "Aliases"
      assert html =~ email_alias.address
    end

    test "searches on change and submit, and clears an empty result", %{
      conn: conn,
      user: user,
      email_alias: email_alias
    } do
      matching_alias =
        alias_fixture(%{user_id: user.id, title: "Amazon", notes: "Shopping receipts 100%"})

      partial_match = alias_fixture(%{user_id: user.id, title: "Amazon", notes: "1000 receipts"})

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#query[phx-debounce='300']")

      view |> form("#alias-search", query: "amazon shopping") |> render_change()
      assert has_element?(view, "#copy-alias-#{matching_alias.id}")
      refute has_element?(view, "#copy-alias-#{email_alias.id}")
      refute has_element?(view, "#copy-alias-#{partial_match.id}")

      view |> form("#alias-search", query: "100%") |> render_submit()
      assert has_element?(view, "#copy-alias-#{matching_alias.id}")
      refute has_element?(view, "#copy-alias-#{partial_match.id}")
      refute has_element?(view, "#copy-alias-#{email_alias.id}")

      view |> form("#alias-search", query: "missing") |> render_submit()
      assert has_element?(view, "h3", "No matching aliases")
      refute has_element?(view, "#aliases")

      view |> element("#clear-alias-search") |> render_click()
      assert has_element?(view, "#query[value='']")
      assert has_element?(view, "#copy-alias-#{matching_alias.id}")
      assert has_element?(view, "#copy-alias-#{email_alias.id}")
      assert has_element?(view, "#copy-alias-#{partial_match.id}")
      refute has_element?(view, "#clear-alias-search")
    end

    test "creates new email_alias", %{conn: conn} do
      {:ok, index_live, _html} =
        conn
        |> live(~p"/")

      {:ok, _view, html} =
        index_live |> element("button", "New alias") |> render_click() |> follow_redirect(conn)

      assert html =~ "Created new alias"
      assert html =~ "@email.shroud.test"
    end

    test "creates new custom alias", %{conn: conn, user: user} do
      custom_domain = custom_domain_fixture(%{user_id: user.id})

      {:ok, index_live, _html} =
        conn
        |> live(~p"/")

      # open the custom alias modal, which sets the domain to create the alias under
      index_live
      |> render_hook("open_custom_alias_modal", %{"text" => "@#{custom_domain.domain}"})

      {:ok, _view, html} =
        index_live
        |> form("form[phx-submit='create_custom_alias']", %{"alias_name" => "john.doe"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Created new alias"
      assert html =~ "john.doe@#{custom_domain.domain}"
    end

    # test "deletes email_alias in listing", %{conn: conn, email_alias: email_alias} do
    #   {:ok, index_live, _html} =
    #     conn
    #     |> live(~p"/")

    #   assert index_live |> element("#alias-#{email_alias.id} a", "Delete") |> render_click()
    #   refute has_element?(index_live, "#alias-#{email_alias.id}")
    # end

    test "shows logging warning when logging is enabled", %{conn: conn, user: user} do
      FunWithFlags.enable(:logging, for_actor: user)

      {:ok, _index_live, html} =
        conn
        |> live(~p"/")

      assert html =~ "Logging is enabled"
    end

    test "shows logging warning when detailed logging is enabled", %{conn: conn, user: user} do
      FunWithFlags.enable(:email_data_logging, for_actor: user)

      {:ok, _index_live, html} =
        conn
        |> live(~p"/")

      assert html =~ "Logging is enabled"
    end
  end
end
