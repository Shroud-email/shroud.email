defmodule ShroudWeb.UserSessionController do
  use ShroudWeb, :controller

  alias Shroud.Accounts
  alias ShroudWeb.UserAuth

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil, page_title: "Log in")
  end

  def new_totp(conn, _params) do
    render(conn, "totp.html", error_message: nil, page_title: "Log in")
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      if user.totp_enabled do
        conn
        |> put_session(:totp_pending_user_params, user_params)
        |> redirect(to: ~p"/users/totp")
      else
        UserAuth.log_in_user(conn, user, user_params)
      end
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      render(conn, "new.html", error_message: "Invalid email or password")
    end
  end

  def create_totp(conn, params) do
    %{"verification_code" => otp} = params
    %{"email" => email} = user_params = get_session(conn, :totp_pending_user_params)
    user = Accounts.get_user_by_email(email)

    if Accounts.TOTP.valid_code?(user, user.totp_secret, otp) do
      conn
      |> put_session(:totp_pending_user_params, nil)
      |> UserAuth.log_in_user(user, user_params)
    else
      render(conn, "totp.html", error_message: "Invalid two-factor authentication code.")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
