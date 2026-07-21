defmodule ShroudWeb.UserSessionControllerTest do
  # Mutates global Application env (cap_*) via enable_cap/disable_cap in the
  # "Cap enabled" describe block below; must run serially to stay isolation-safe.
  use ShroudWeb.ConnCase, async: false

  alias Shroud.Accounts.User
  alias Shroud.Repo
  import Shroud.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/log_in" do
    test "renders log in page", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")
      response = html_response(conn, 200)
      assert response =~ "Sign in"
      assert response =~ "sign up for free"
      assert response =~ "Forgot your password?</a>"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/users/log_in")
      assert redirected_to(conn) == "/"
    end
  end

  describe "POST /users/log_in" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/users/confirm")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ "Settings</a>"
      assert response =~ "Log out</a>"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_shroud_web_user_remember_me"]
      assert redirected_to(conn) == "/users/confirm"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      Repo.update!(User.confirm_changeset(user))

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
    end

    test "emits error message with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "Sign in"
      assert response =~ "Invalid email or password"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == "/users/log_in"
      refute get_session(conn, :user_token)
      assert Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == "/users/log_in"
      refute get_session(conn, :user_token)
      assert Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end

  describe "POST /users/log_in with Cap enabled" do
    defp enable_cap do
      Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
      Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
      Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
    end

    defp disable_cap do
      Application.put_env(:shroud, :cap_instance_url, nil)
      Application.put_env(:shroud, :cap_site_key, nil)
      Application.put_env(:shroud, :cap_secret_key, nil)
    end

    test "rejects a forged POST with no cap-token", %{conn: conn, user: user} do
      enable_cap()

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/users/log_in"
      assert Flash.get(conn.assigns.flash, :error) =~ "verification"
    after
      disable_cap()
    end

    test "logs in when cap-token verifies", %{conn: conn, user: user} do
      enable_cap()

      Req.Test.stub(Shroud.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => true})
      end)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()},
          "cap-token" => "valid-token"
        })

      assert get_session(conn, :user_token)
    after
      disable_cap()
    end
  end
end
