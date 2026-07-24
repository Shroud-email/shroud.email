defmodule ShroudWeb.UserRegistrationControllerTest do
  # Mutates global Application env (cap_*) via enable_cap/disable_cap in the
  # "Cap enabled" describe block below; must run serially to stay isolation-safe.
  use ShroudWeb.ConnCase, async: false

  import Shroud.AccountsFixtures

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Sign up"
      assert response =~ "Log in</a>"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")
      assert redirected_to(conn) == "/"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and logs the user in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/users/confirm")
      response = html_response(conn, 200)
      assert response =~ email
      assert response =~ "Settings</a>"
      assert response =~ "Log out</a>"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces", "password" => "too short"}
        })

      response = html_response(conn, 200)
      assert response =~ "Sign up"
      assert response =~ "must have the @ sign and no spaces"
      assert response =~ "should be at least 12 character"
    end

    test "creates a lifetime user", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email, status: :lifetime)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/users/confirm")
      assert conn.assigns.current_user.status == :lifetime
    end
  end

  describe "POST /users/register with Cap enabled" do
    test "rejects a forged POST with no cap-token", %{conn: conn} do
      enable_cap()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: unique_user_email())
        })

      assert redirected_to(conn) == "/users/register"
      assert Flash.get(conn.assigns.flash, :error) =~ "verification"
    after
      disable_cap()
    end

    test "creates account when cap-token verifies", %{conn: conn} do
      enable_cap()

      Req.Test.stub(Shroud.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => true})
      end)

      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email),
          "cap-token" => "valid-token"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"
    after
      disable_cap()
    end
  end
end
