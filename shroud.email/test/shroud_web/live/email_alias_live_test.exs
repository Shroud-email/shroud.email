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

    test "shows unverified domains as disabled, including without aliases", %{
      conn: conn,
      user: user,
      email_alias: email_alias
    } do
      unverified = custom_domain_fixture(%{user_id: user.id, ownership_verified_at: nil})
      partial = custom_domain_fixture(%{user_id: user.id, dkim_verified_at: nil})

      expired =
        custom_domain_fixture(%{
          user_id: user.id,
          mx_verified_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.truncate(:second)
            |> NaiveDateTime.add(-25, :hour)
        })

      other_user_domain = custom_domain_fixture()

      for empty? <- [false, true] do
        if empty?, do: Shroud.Aliases.delete_email_alias(email_alias.id)
        {:ok, view, _html} = live(conn, ~p"/")

        assert has_element?(view, "button[aria-haspopup='true']", "Open menu")
        assert has_element?(view, "#new-alias-default-domain[role='menuitem']")

        for domain <- [unverified, partial, expired] do
          selector = "#new-alias-domain-#{domain.id}"
          assert has_element?(view, selector <> "[aria-disabled='true']", "@#{domain.domain}")

          assert has_element?(
                   view,
                   selector <> "[aria-label='@#{domain.domain}: Domain is not verified']"
                 )

          assert has_element?(
                   view,
                   selector <> "[x-tooltip\\.raw\\.placement\\.left='Domain is not verified']"
                 )

          refute has_element?(view, selector <> "[phx-click]")
        end

        refute has_element?(view, "#new-alias-domain-#{other_user_domain.id}")
      end
    end

    test "does not show a domain dropdown without custom domains", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "button[aria-haspopup='true']", "Open menu")
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

    test "paginates without retaining previous rows and restores pages from the URL", %{
      conn: conn,
      user: user,
      email_alias: oldest
    } do
      aliases = for _ <- 1..40, do: alias_fixture(%{user_id: user.id})
      newest = List.last(aliases)
      second_page_first = Enum.at(aliases, 19)

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#aliases > tr:nth-child(20)")
      refute has_element?(view, "#aliases > tr:nth-child(21)")
      assert has_element?(view, "#copy-alias-#{newest.id}")
      refute has_element?(view, "#copy-alias-#{second_page_first.id}")
      assert has_element?(view, "#alias-page-range", "Showing 1–20 of 41 aliases")
      assert has_element?(view, "#alias-page-range[aria-live='polite'][aria-atomic='true']")
      assert has_element?(view, "#alias-page-summary[aria-live='polite'][aria-atomic='true']")
      refute has_element?(view, "#alias-page-previous")

      view |> element("#alias-page-next") |> render_click()
      assert_patch(view, ~p"/?page=2")
      assert has_element?(view, "#alias-page-2[aria-current='page']")
      assert has_element?(view, "#copy-alias-#{second_page_first.id}")
      refute has_element?(view, "#copy-alias-#{newest.id}")
      assert has_element?(view, "#alias-page-range", "Showing 21–40 of 41 aliases")

      {:ok, restored, _html} = live(conn, ~p"/?page=2")
      assert has_element?(restored, "#copy-alias-#{second_page_first.id}")
      refute has_element?(restored, "#copy-alias-#{newest.id}")

      view |> element("#alias-page-3") |> render_click()
      assert_patch(view, ~p"/?page=3")
      assert has_element?(view, "#copy-alias-#{oldest.id}")
      refute has_element?(view, "#aliases > tr:nth-child(2)")
      refute has_element?(view, "#alias-page-next")
      assert has_element?(view, "#alias-page-range", "Showing 41–41 of 41 aliases")

      view |> element("#alias-page-previous") |> render_click()
      assert_patch(view, ~p"/?page=2")
      assert has_element?(view, "#copy-alias-#{second_page_first.id}")
      refute has_element?(view, "#copy-alias-#{oldest.id}")

      render_patch(view, ~p"/?page=999")
      assert_patch(view, ~p"/?page=3")
      assert has_element?(view, "#copy-alias-#{oldest.id}")
      assert has_element?(view, "#alias-page-range", "Showing 41–41 of 41 aliases")
      assert has_element?(view, "#alias-page-summary", "Page 3 of 3")
    end

    test "search resets the page and paginates all matches while retaining the query", %{
      conn: conn,
      user: user
    } do
      matches = for _ <- 1..25, do: alias_fixture(%{user_id: user.id, notes: "100% receipts"})
      for _ <- 1..20, do: alias_fixture(%{user_id: user.id, notes: "1000 receipts"})

      {:ok, view, _html} = live(conn, ~p"/?page=3")
      view |> form("#alias-search", query: "100%") |> render_submit()
      assert_patch(view, ~p"/?#{[page: 1, query: "100%"]}")
      assert has_element?(view, "#alias-page-range", "Showing 1–20 of 25 aliases")
      assert has_element?(view, "#copy-alias-#{List.last(matches).id}")
      refute has_element?(view, "#copy-alias-#{hd(matches).id}")

      view |> element("#alias-page-next") |> render_click()
      assert_patch(view, ~p"/?#{[page: 2, query: "100%"]}")
      assert has_element?(view, "#query[value='100%']")
      assert has_element?(view, "#copy-alias-#{hd(matches).id}")
      assert has_element?(view, "#aliases > tr:nth-child(5)")
      refute has_element?(view, "#aliases > tr:nth-child(6)")
      assert has_element?(view, "#alias-page-range", "Showing 21–25 of 25 aliases")

      {:ok, restored, _html} = live(conn, ~p"/?#{[page: 2, query: "100%"]}")
      assert has_element?(restored, "#query[value='100%']")
      assert has_element?(restored, "#copy-alias-#{hd(matches).id}")

      view |> form("#alias-search", query: "missing") |> render_change()
      assert_patch(view, ~p"/?#{[page: 1, query: "missing"]}")
      refute has_element?(view, "#alias-pagination")
      assert has_element?(view, "#clear-alias-search")
      view |> element("#clear-alias-search") |> render_click()
      assert_patch(view, ~p"/?page=1")
      assert has_element?(view, "#alias-page-range", "Showing 1–20 of 46 aliases")
    end

    test "normalizes invalid and out-of-range pages and hides single-page navigation", %{
      conn: conn,
      email_alias: email_alias
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#alias-pagination")

      for page <- ["0", "-2", "abc", "2oops", "999999999999999999999999999"] do
        render_patch(view, ~p"/?#{[page: page]}")
        assert_patch(view, ~p"/?page=1")
        assert has_element?(view, "#copy-alias-#{email_alias.id}")
        refute has_element?(view, "#alias-pagination")
      end

      render_patch(view, ~p"/?#{[page: 999, query: "missing"]}")
      assert_patch(view, ~p"/?#{[page: 1, query: "missing"]}")
      assert has_element?(view, "h3", "No matching aliases")
      refute has_element?(view, "#aliases")
      refute has_element?(view, "#alias-pagination")
    end

    test "compact pagination hides ellipses from assistive technology", %{conn: conn, user: user} do
      for _ <- 1..140, do: alias_fixture(%{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/?page=4")

      for page <- [1, 3, 4, 5, 8], do: assert(has_element?(view, "#alias-page-#{page}"))
      for page <- [2, 6, 7], do: refute(has_element?(view, "#alias-page-#{page}"))
      assert has_element?(view, "#alias-pagination span[aria-hidden='true']", "…")
      refute has_element?(view, "#alias-pagination span:not([aria-hidden='true'])", "…")
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
      |> element("#new-alias-domain-#{custom_domain.id}:not([aria-disabled])")
      |> render_click()

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
