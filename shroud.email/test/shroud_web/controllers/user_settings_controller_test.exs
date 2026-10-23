defmodule ShroudWeb.UserSettingsControllerTest do
  use ShroudWeb.ConnCase, async: false

  alias Shroud.Accounts
  import Phoenix.LiveViewTest
  import Shroud.AccountsFixtures

  setup :register_and_log_in_user

  describe "DELETE /settings/account" do
    setup do
      bypass = Bypass.open()
      original = Application.fetch_env!(:shroud, :billing)

      Application.put_env(
        :shroud,
        :billing,
        Keyword.put(original, :paddle_base_url, "http://localhost:#{bypass.port}")
      )

      on_exit(fn -> Application.put_env(:shroud, :billing, original) end)
      %{bypass: bypass}
    end

    test "requires authentication, confirmation and the current password", %{
      conn: conn,
      user: user
    } do
      assert redirected_to(delete(build_conn(), ~p"/settings/account")) == ~p"/users/log_in"

      for params <- [
            %{},
            %{current_password: valid_user_password()},
            %{current_password: valid_user_password(), confirm_deletion: "false"},
            %{confirm_deletion: "true"},
            %{current_password: "wrong password", confirm_deletion: "true"}
          ] do
        response = delete(conn, ~p"/settings/account", params)

        if params[:confirm_deletion] == "true" do
          assert redirected_to(response) == ~p"/settings/account#danger-zone"
          refute Flash.get(response.assigns.flash, :error)
          {:ok, view, _} = live(recycle(response), ~p"/settings/account")

          assert has_element?(
                   view,
                   "#delete-account-password-error[role=alert]",
                   "Current password is incorrect"
                 )

          assert has_element?(
                   view,
                   "#delete-account-password[aria-invalid=true][aria-describedby=delete-account-password-error]"
                 )

          refute has_element?(view, "[data-kind=error]")
        else
          assert redirected_to(response) == ~p"/settings/account"
          assert Flash.get(response.assigns.flash, :error)
        end

        assert Accounts.get_user(user.id)
        assert Accounts.get_user_by_session_token(get_session(conn, :user_token))
      end

      assert response(delete(conn, ~p"/settings/account", %{confirm_deletion: "true"}), 429)
    end

    test "cancels immediately without a refund, deletes only the signed-in account and clears its session",
         %{conn: conn, user: user, bypass: bypass} do
      user
      |> Accounts.User.paddle_changeset(%{paddle_subscription_id: "sub_delete"})
      |> Shroud.Repo.update!()

      other = user_fixture()

      Bypass.expect_once(bypass, "GET", "/subscriptions/sub_delete", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{data: %{id: "sub_delete", status: "active"}}))
        |> Plug.Conn.put_resp_header("content-type", "application/json")
      end)

      Bypass.expect_once(bypass, "POST", "/subscriptions/sub_delete/cancel", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test_key"]
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"effective_from" => "immediately"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: %{id: "sub_delete", status: "canceled"}}))
      end)

      deleted =
        delete(conn, ~p"/settings/account", %{
          current_password: valid_user_password(),
          confirm_deletion: "true",
          user_id: other.id
        })

      assert redirected_to(deleted) == ~p"/users/log_in"
      refute get_session(deleted, :user_token)
      refute Accounts.get_user(user.id)
      assert Accounts.get_user(other.id)
      refute Accounts.get_user_by_session_token(get_session(conn, :user_token))
      assert Flash.get(deleted.assigns.flash, :info) == "Your account has been deleted."
    end

    test "billing failures preserve the account and its data, and an already-canceled subscription can be retried",
         %{conn: conn, user: user, bypass: bypass} do
      user
      |> Accounts.User.paddle_changeset(%{paddle_subscription_id: "sub_delete"})
      |> Shroud.Repo.update!()

      email_alias = Shroud.AliasesFixtures.alias_fixture(%{user_id: user.id})

      params = %{current_password: valid_user_password(), confirm_deletion: "true"}

      for {status, body} <- [
            {503, %{error: %{code: "unavailable"}}},
            {200, %{data: %{id: "sub_delete", status: "active"}}},
            {200, %{data: %{id: "sub_other", status: "canceled"}}}
          ] do
        Bypass.expect_once(bypass, "GET", "/subscriptions/sub_delete", fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{data: %{id: "sub_delete", status: "active"}}))
        end)

        Bypass.expect_once(bypass, "POST", "/subscriptions/sub_delete/cancel", fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(status, Jason.encode!(body))
        end)

        failed = delete(conn, ~p"/settings/account", params)
        assert redirected_to(failed) == ~p"/settings/account"
        assert Flash.get(failed.assigns.flash, :error) =~ "has not been deleted"
        assert Accounts.get_user_by_alias(email_alias.address).id == user.id
        assert Accounts.get_user_by_session_token(get_session(conn, :user_token))
      end

      Bypass.expect_once(bypass, "GET", "/subscriptions/sub_delete", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: %{id: "sub_delete", status: "canceled"}}))
      end)

      assert redirected_to(delete(conn, ~p"/settings/account", params)) == ~p"/users/log_in"
      refute Accounts.get_user(user.id)
    end

    test "paid pending checkouts block deletion; unpaid checkouts are closed before deletion", %{
      conn: conn,
      user: user,
      bypass: bypass
    } do
      user
      |> Accounts.User.paddle_changeset(%{paddle_checkout_transaction_id: "txn_delete"})
      |> Shroud.Repo.update!()

      params = %{current_password: valid_user_password(), confirm_deletion: "true"}

      Bypass.expect_once(bypass, "GET", "/transactions/txn_delete", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: %{id: "txn_delete", status: "paid"}}))
      end)

      failed = delete(conn, ~p"/settings/account", params)
      assert redirected_to(failed) == ~p"/settings/account"
      assert Flash.get(failed.assigns.flash, :error) =~ "still being processed"
      assert Accounts.get_user(user.id)

      Bypass.expect_once(bypass, "GET", "/transactions/txn_delete", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: %{id: "txn_delete", status: "ready"}}))
      end)

      Bypass.expect_once(bypass, "PATCH", "/transactions/txn_delete", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"status" => "canceled"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{data: %{id: "txn_delete", status: "canceled"}}))
      end)

      assert redirected_to(delete(conn, ~p"/settings/account", params)) == ~p"/users/log_in"
      refute Accounts.get_user(user.id)
    end
  end

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
