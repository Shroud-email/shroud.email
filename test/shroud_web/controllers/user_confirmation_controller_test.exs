defmodule ShroudWeb.UserConfirmationControllerTest do
  use ShroudWeb.ConnCase, async: true

  alias Shroud.Accounts
  alias Shroud.Repo
  import Shroud.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/confirm" do
    test "redirects to login page for unauthenticated user", %{conn: conn} do
      conn = get(conn, Routes.user_confirmation_path(conn, :new))

      assert redirected_to(conn) == "/users/log_in"
    end

    test "renders the resend confirmation page when authenticated", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      conn = get(conn, Routes.user_confirmation_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Almost there"
      assert response =~ "We sent you an email with a confirmation link."
    end
  end

  describe "POST /users/confirm" do
    @tag :capture_log
    test "sends a new confirmation token", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/users/confirm"
      assert Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Repo.get_by!(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "redirects if User is confirmed", %{conn: conn, user: user} do
      Repo.update!(Accounts.User.confirm_changeset(user))
      conn = log_in_user(conn, user)

      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/"
      refute Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
    end
  end

  describe "GET /users/confirm/:token" do
    test "renders the confirmation page", %{conn: conn} do
      conn = get(conn, Routes.user_confirmation_path(conn, :edit, "some-token"))
      response = html_response(conn, 200)
      assert response =~ "Confirm account"

      form_action = Routes.user_confirmation_path(conn, :update, "some-token")
      assert response =~ "action=\"#{form_action}\""
    end
  end

  describe "POST /users/confirm/:token" do
    test "confirms the given token once", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      conn = post(conn, Routes.user_confirmation_path(conn, :update, token))
      assert redirected_to(conn) == "/"
      assert Flash.get(conn.assigns.flash, :info) =~ "Account confirmed."
      assert Accounts.get_user!(user.id).confirmed_at
      refute get_session(conn, :user_token)
      assert Repo.all(Accounts.UserToken) == []

      # When not logged in
      conn = post(conn, Routes.user_confirmation_path(conn, :update, token))
      assert redirected_to(conn) == "/"

      assert Flash.get(conn.assigns.flash, :error) =~
               "User confirmation link is invalid or it has expired"

      # When logged in
      conn =
        build_conn()
        |> log_in_user(user)
        |> post(Routes.user_confirmation_path(conn, :update, token))

      assert redirected_to(conn) == "/"
      refute Flash.get(conn.assigns.flash, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      conn = post(conn, Routes.user_confirmation_path(conn, :update, "oops"))
      assert redirected_to(conn) == "/"

      assert Flash.get(conn.assigns.flash, :error) =~
               "User confirmation link is invalid or it has expired"

      refute Accounts.get_user!(user.id).confirmed_at
    end
  end
end
