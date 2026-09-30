defmodule ShroudWeb.UserSettingsControllerTest do
  use ShroudWeb.ConnCase, async: true

  alias Shroud.Accounts
  import Shroud.AccountsFixtures

  setup :register_and_log_in_user

  describe "GET /settings/account" do
    test "renders settings page", %{conn: conn} do
      conn = get(conn, ~p"/settings/account")
      response = html_response(conn, 200)
      assert response =~ "Account settings"
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/settings/account")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "PUT /settings/password" do
    test "updates the user password and resets tokens", %{conn: conn, user: user} do
      new_password_conn =
        put(conn, ~p"/settings/password", %{
          "current_password" => valid_user_password(),
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(new_password_conn) == ~p"/settings/security"
      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)
      assert Flash.get(new_password_conn.assigns.flash, :info) =~ "Password updated successfully"
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not update password on invalid data", %{conn: conn} do
      old_password_conn =
        put(conn, ~p"/settings/password", %{
          "current_password" => "invalid",
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert redirected_to(old_password_conn) == ~p"/settings/security"
      assert Flash.get(old_password_conn.assigns.flash, :error) =~ "Password could not be updated"

      assert get_session(old_password_conn, :user_token) == get_session(conn, :user_token)
    end
  end

  describe "GET /settings/confirm_email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, ~p"/settings/confirm_email/#{token}")
      assert redirected_to(conn) == ~p"/settings/account"
      assert Flash.get(conn.assigns.flash, :info) =~ "Email changed successfully"
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, ~p"/settings/confirm_email/#{token}")
      assert redirected_to(conn) == ~p"/settings/account"

      assert Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, ~p"/settings/confirm_email/oops")
      assert redirected_to(conn) == ~p"/settings/account"

      assert Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/settings/confirm_email/#{token}")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
