defmodule ShroudWeb.MailserverHealthLiveTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Shroud.Repo

  setup do
    original = Application.get_env(:shroud, :mailserver_health_checker)

    Application.put_env(:shroud, :mailserver_health_checker, fn ->
      %{
        checked_at: ~U[2026-09-25 10:00:00Z],
        results: [
          %{name: "MX", status: :pass, detail: "mx.example"},
          %{name: "STARTTLS", status: :fail, detail: "Not advertised"}
        ]
      }
    end)

    on_exit(fn ->
      if original do
        Application.put_env(:shroud, :mailserver_health_checker, original)
      else
        Application.delete_env(:shroud, :mailserver_health_checker)
      end
    end)

    :ok
  end

  test "only admins can access the diagnostics", %{conn: conn} do
    assert get(conn, "/admin/mailserver").status == 302

    %{conn: user_conn} = register_and_log_in_user(%{conn: build_conn()})
    assert get(user_conn, "/admin/mailserver").status == 302
  end

  test "renders independent results and refreshes on demand", %{conn: conn} do
    %{conn: user_conn, user: user} = register_and_log_in_user(%{conn: conn})
    user |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()

    {:ok, view, _html} = live(user_conn, "/admin/mailserver")
    render_async(view)

    assert has_element?(view, "#mailserver-results [data-status='pass']")
    assert has_element?(view, "#mailserver-results [data-status='fail']")
    assert has_element?(view, "#mailserver-results", "Not advertised")

    view |> element("#mailserver-refresh") |> render_click()
    render_async(view)
    assert has_element?(view, "#mailserver-results [data-status='fail']")
  end
end
