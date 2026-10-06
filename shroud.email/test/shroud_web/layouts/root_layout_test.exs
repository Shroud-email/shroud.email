defmodule ShroudWeb.RootLayoutTest do
  use ShroudWeb.ConnCase, async: false

  import Shroud.AccountsFixtures
  alias Shroud.Repo

  test "analytics is omitted when disabled", %{conn: conn} do
    html = conn |> get(~p"/users/log_in") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(html, "meta[name='openpanel-client-id']") |> Enum.count() == 0
  end

  test "analytics exposes only public configuration and pseudonymous ID", %{conn: conn} do
    previous = Application.get_env(:shroud, :openpanel)

    Application.put_env(:shroud, :openpanel,
      enabled: true,
      client_id: "test-client",
      api_url: "https://panel.example.test/api",
      client_secret: "private-secret"
    )

    on_exit(fn -> Application.put_env(:shroud, :openpanel, previous) end)
    user = user_fixture() |> Shroud.Accounts.User.confirm_changeset() |> Repo.update!()
    html = conn |> log_in_user(user) |> get(~p"/settings/billing") |> html_response(200)
    document = LazyHTML.from_document(html)

    assert LazyHTML.query(document, "meta[name='openpanel-client-id']")
           |> LazyHTML.attribute("content") == ["test-client"]

    assert LazyHTML.query(document, "meta[name='openpanel-profile-id']")
           |> LazyHTML.attribute("content") == [Shroud.Analytics.profile_id(user.id)]

    refute LazyHTML.query(document, "meta[name='openpanel-profile-id']")
           |> LazyHTML.attribute("content") == [to_string(user.id)]

    assert LazyHTML.query(document, "meta[name='referrer']") |> LazyHTML.attribute("content") ==
             ["strict-origin-when-cross-origin"]

    refute html =~ "private-secret"
  end

  describe "root layout with Paddle config missing" do
    test "renders the page without crashing when paddle_client_token is nil", %{conn: conn} do
      # Simulate a self-hosting user who hasn't configured Paddle.
      original = Application.get_env(:shroud, :billing)
      Application.put_env(:shroud, :billing, Keyword.put(original, :paddle_client_token, nil))

      on_exit(fn -> Application.put_env(:shroud, :billing, original) end)

      user = user_fixture() |> Shroud.Accounts.User.confirm_changeset() |> Repo.update!()
      conn = conn |> log_in_user(user) |> get(~p"/settings/billing")

      assert html_response(conn, 200)
    end

    test "renders the page without crashing when billing config is entirely missing", %{
      conn: conn
    } do
      original = Application.get_env(:shroud, :billing)
      Application.delete_env(:shroud, :billing)

      on_exit(fn -> Application.put_env(:shroud, :billing, original) end)

      user = user_fixture() |> Shroud.Accounts.User.confirm_changeset() |> Repo.update!()
      conn = conn |> log_in_user(user) |> get(~p"/settings/billing")

      assert html_response(conn, 200)
    end
  end
end
