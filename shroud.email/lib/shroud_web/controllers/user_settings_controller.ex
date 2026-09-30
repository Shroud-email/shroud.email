defmodule ShroudWeb.UserSettingsController do
  use ShroudWeb, :controller

  alias Shroud.Accounts
  alias ShroudWeb.UserAuth

  def redirect_to_account(conn, _params) do
    redirect(conn, to: ~p"/settings/account")
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/settings/account")

      :error ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/settings/account")
    end
  end

  # A regular HTTP request is required to renew the session after changing a password.
  def update_password(conn, %{"current_password" => password, "user" => params}) do
    case Accounts.update_user_password(conn.assigns.current_user, password, params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, ~p"/settings/security")
        |> UserAuth.log_in_user(user)

      {:error, _changeset} ->
        conn
        |> put_flash(
          :error,
          "Password could not be updated. Please check your password and try again."
        )
        |> redirect(to: ~p"/settings/security")
    end
  end
end
