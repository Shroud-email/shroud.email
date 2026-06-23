defmodule ShroudWeb.SpamEmailLiveTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.EmailFixtures
  import Shroud.AliasesFixtures

  alias Shroud.Aliases

  describe "Index" do
    setup :register_and_log_in_user

    setup %{user: user} do
      email_alias = alias_fixture(%{user_id: user.id})

      %{
        email_alias: email_alias,
        spam_email: spam_email_fixture(%{}, user, email_alias)
      }
    end

    test "lists spam emails", %{conn: conn, spam_email: spam_email} do
      {:ok, _view, html} = live(conn, ~p"/detention")

      assert html =~ "Spam"
      assert html =~ spam_email.subject
    end

    test "blocks a sender", %{conn: conn, spam_email: spam_email, email_alias: email_alias} do
      {:ok, view, _html} = live(conn, ~p"/detention")

      html =
        view
        |> element("button[phx-value-sender='#{spam_email.from}']")
        |> render_click()

      assert html =~ "Going forward, this alias will block emails from this sender."

      reloaded = Aliases.get_email_alias_by_address!(email_alias.address)
      assert spam_email.from in reloaded.blocked_addresses
    end

    test "shows an error flash when blocking the sender fails", %{conn: conn, user: user} do
      # A sender without an @ sign fails the blocked_addresses changeset, so
      # block_sender/2 returns {:error, _}. The LiveView must still return a
      # noreply (rather than crashing) and surface an error.
      spam_email = spam_email_fixture(%{from: "invalid sender"}, user)

      {:ok, view, _html} = live(conn, ~p"/detention")

      html =
        view
        |> element("button[phx-value-sender='#{spam_email.from}']")
        |> render_click()

      assert html =~ "Something went wrong."
      assert has_element?(view, "button[phx-value-sender='#{spam_email.from}']")
    end
  end
end
