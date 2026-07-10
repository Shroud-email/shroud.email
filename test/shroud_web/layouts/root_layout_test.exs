defmodule ShroudWeb.RootLayoutTest do
  use ShroudWeb.ConnCase, async: false

  import Shroud.AccountsFixtures
  alias Shroud.Repo

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
