defmodule ShroudWeb.InboxLiveTest do
  use ShroudWeb.ConnCase
  import Phoenix.LiveViewTest
  import Mox
  import Shroud.AliasesFixtures
  import Shroud.InboxesFixtures
  alias Shroud.{Inboxes, Repo, Vault}
  alias Shroud.S3.MockS3Client

  setup :register_and_log_in_user
  setup :set_mox_global
  setup :verify_on_exit!

  setup %{user: user} do
    inbox = alias_fixture(%{user_id: user.id, delivery_mode: :inbox})
    %{inbox: inbox}
  end

  test "flag hides controls, rejects creation events and direct inbox/download access", %{
    conn: conn,
    user: user,
    inbox: inbox
  } do
    FunWithFlags.disable(:agent_inboxes, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/")
    refute has_element?(view, "#new-inbox")
    count = Shroud.Aliases.count_aliases(user)
    render_click(view, "add_inbox")
    assert Shroud.Aliases.count_aliases(user) == count
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/inbox/#{inbox.address}")
    message = message_fixture(inbox)
    assert conn |> get(~p"/inbox/messages/#{message.id}/attachments/0") |> response(404)
  end

  test "flagged creation makes an inbox with indefinite retention", %{conn: conn, user: user} do
    FunWithFlags.enable(:agent_inboxes, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/")
    view |> element("#new-inbox") |> render_click()
    assert_redirect(view)
    assert [%{delivery_mode: :inbox, retention_days: nil} | _] = Shroud.Aliases.list_aliases(user)
  end

  test "opening mail and downloading attachments preserve unread state; explicit actions change it",
       %{conn: conn, user: user, inbox: inbox} do
    FunWithFlags.enable(:agent_inboxes, for_actor: user)
    message = message_fixture(inbox)

    stub(MockS3Client, :get_email!, fn key ->
      assert key == message.storage_key
      Vault.encrypt!(email_with_attachment())
    end)

    {:ok, view, _} = live(conn, ~p"/inbox/#{inbox.address}/messages/#{message.id}")
    assert has_element?(view, "#message-body", "09:45")
    refute has_element?(view, "#message-body script")
    assert has_element?(view, "#attachment-0", "itinerary.pdf")
    assert has_element?(view, "#toggle-read", "Mark read")
    refute Repo.reload!(message).read

    downloaded = get(conn, ~p"/inbox/messages/#{message.id}/attachments/0")
    assert response(downloaded, 200) == <<"%PDF-1.4\n", 0, 1, 2>>

    assert get_resp_header(downloaded, "content-disposition") == [
             "attachment; filename=\"itinerary.pdf\""
           ]

    assert get_resp_header(downloaded, "cache-control") == ["private, no-store"]
    refute Repo.reload!(message).read

    view |> element("#toggle-read") |> render_click()
    assert Repo.reload!(message).read
    assert has_element?(view, "#toggle-read", "Mark unread")
    view |> element("#toggle-read") |> render_click()
    refute Repo.reload!(message).read
    view |> element("#delete-message") |> render_click()
    assert Inboxes.list_messages(user, inbox.address).entries == []
    assert Repo.reload!(message).deleted_at
  end

  test "retention form supports finite retention and resetting to forever", %{
    conn: conn,
    user: user,
    inbox: inbox
  } do
    FunWithFlags.enable(:agent_inboxes, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/inbox/#{inbox.address}")
    view |> form("#inbox-retention", email_alias: %{retention_days: "30"}) |> render_submit()
    assert Repo.reload!(inbox).retention_days == 30
    view |> form("#inbox-retention", email_alias: %{retention_days: ""}) |> render_submit()
    assert is_nil(Repo.reload!(inbox).retention_days)
  end

  test "other users cannot open an inbox or download its attachments", %{conn: conn, user: user} do
    FunWithFlags.enable(:agent_inboxes, for_actor: user)
    outsider = Shroud.AccountsFixtures.user_fixture()
    inbox = alias_fixture(%{user_id: outsider.id, delivery_mode: :inbox})
    message = message_fixture(inbox)
    assert_error_sent 404, fn -> get(conn, ~p"/inbox/#{inbox.address}") end
    assert_error_sent 404, fn -> get(conn, ~p"/inbox/messages/#{message.id}/attachments/0") end
  end
end
