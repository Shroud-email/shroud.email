defmodule ShroudWeb.UserSettingsController do
  use ShroudWeb, :controller

  alias Shroud.Accounts
  alias Shroud.Accounts.TOTP
  alias ShroudWeb.UserAuth

  plug :assign_email_and_password_changesets
  plug :assign_totp_fields
  plug :put_layout, "settings.html"

  def redirect_to_account(conn, _params) do
    redirect(conn, to: Routes.user_settings_path(conn, :account))
  end

  def account(conn, _params) do
    render(conn, "account.html", page_title: "Account settings")
  end

  def security(conn, _params) do
    otp_qr_code =
      if get_session(conn, :totp_secret) do
        secret = get_session(conn, :totp_secret)

        conn.assigns.current_user
        |> TOTP.otp_uri(secret)
        |> EQRCode.encode()
        |> EQRCode.svg(width: 264)
      end

    totp_backup_codes = get_session(conn, :totp_backup_codes)

    conn
    |> put_session(:totp_backup_codes, nil)
    |> render("security.html",
      page_title: "Security settings",
      otp_qr_code: otp_qr_code,
      totp_backup_codes: totp_backup_codes
    )
  end

  def billing(conn, _params) do
    render(conn, "billing.html", page_title: "Billing settings")
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: Routes.user_settings_path(conn, :account))

      :error ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: Routes.user_settings_path(conn, :account))
    end
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          &Routes.user_settings_url(conn, :confirm_email, &1)
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: Routes.user_settings_path(conn, :account))

      {:error, changeset} ->
        render(conn, "account.html", email_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, Routes.user_settings_path(conn, :security))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, "security.html", password_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "generate_totp_secret"}) do
    secret = TOTP.create_secret()

    conn
    |> put_session(:totp_secret, secret)
    |> redirect(to: Routes.user_settings_path(conn, :security))
  end

  def update(conn, %{"action" => "enable_totp"} = params) do
    %{"verification_code" => otp} = params
    user = conn.assigns.current_user
    secret = get_session(conn, :totp_secret)

    if TOTP.valid_code?(user, secret, otp) do
      backup_codes = TOTP.enable_totp!(user, secret)

      conn
      |> put_session(:totp_secret, nil)
      |> put_session(:totp_backup_codes, backup_codes)
      |> put_flash(:info, "Enabled two-factor authentication.")
      |> UserAuth.fetch_current_user([])
      |> redirect(to: Routes.user_settings_path(conn, :security))
    else
      conn
      |> put_session(:totp_secret, nil)
      |> put_flash(:error, "Invalid two-factor authentication code.")
      |> redirect(to: Routes.user_settings_path(conn, :security))
    end
  end

  def update(conn, %{"action" => "disable_totp"} = params) do
    %{"verification_code" => otp} = params
    user = conn.assigns.current_user

    if TOTP.valid_code?(user, user.totp_secret, otp) do
      TOTP.disable_totp!(user)

      conn
      |> put_flash(:info, "Disabled two-factor authentication.")
      |> UserAuth.fetch_current_user([])
      |> redirect(to: Routes.user_settings_path(conn, :security))
    else
      conn
      |> put_flash(:error, "Invalid two-factor authentication code.")
      |> redirect(to: Routes.user_settings_path(conn, :security))
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end

  defp assign_totp_fields(conn, _opts) do
    conn
    |> assign(:otp_qr_code, nil)
    |> assign(:otp_backup_codes, nil)
  end
end
