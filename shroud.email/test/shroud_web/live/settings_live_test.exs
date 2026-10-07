defmodule ShroudWeb.SettingsLiveTest do
  use ShroudWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Shroud.{AccountsFixtures, AliasesFixtures}

  alias Shroud.{Accounts, Billing, Repo}
  alias Shroud.Accounts.{TOTP, User}

  setup :register_and_log_in_user

  test "unflagged users cannot see or submit email preferences", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/settings/account")
    refute has_element?(view, "#email-preferences-form")

    render_submit(view, "update_email_preferences", %{"user" => %{"email_branding" => "false"}})

    assert has_element?(
             view,
             "#notification-source [data-kind=error]",
             "Email preferences are not available."
           )

    assert Repo.reload!(user).email_branding
  end

  test "revoking the flag rejects submissions from an already open form", %{
    conn: conn,
    user: user
  } do
    FunWithFlags.enable(:email_branding_preferences, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/settings/account")
    assert has_element?(view, "#email-preferences-form")
    FunWithFlags.disable(:email_branding_preferences, for_actor: user)

    view
    |> form("#email-preferences-form", user: %{email_branding: "false"})
    |> render_submit()

    refute has_element?(view, "#email-preferences-form")

    assert has_element?(
             view,
             "#notification-source [data-kind=error]",
             "Email preferences are not available."
           )

    assert Repo.reload!(user).email_branding
  end

  test "email branding can be disabled and enabled and survives reloads", %{
    conn: conn,
    user: user
  } do
    FunWithFlags.enable(:email_branding_preferences, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/settings/account")
    assert has_element?(view, "#user_email_branding[checked]")

    for enabled <- [false, true] do
      view
      |> form("#email-preferences-form", user: %{email_branding: to_string(enabled)})
      |> render_submit()

      assert Repo.reload!(user).email_branding == enabled

      assert has_element?(
               view,
               "#notification-source [data-kind=info]",
               "Email preferences updated."
             )

      {:ok, reloaded, _} = live(conn, ~p"/settings/account")
      assert has_element?(reloaded, "#user_email_branding[checked]") == enabled
    end
  end

  test "invalid email branding is rejected in place", %{conn: conn, user: user} do
    FunWithFlags.enable(:email_branding_preferences, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/settings/account")

    render_submit(view, "update_email_preferences", %{"user" => %{"email_branding" => "invalid"}})

    assert has_element?(view, "#email-preferences-form .invalid-feedback", "is invalid")
    assert Repo.reload!(user).email_branding
  end

  test "repeated confirmations stack independently and errors have no expiry", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings/appearance")
    notifications = find_live_child(view, "notifications")

    render_submit(view, "update_theme", %{"theme" => "dark"})

    [first_source_id] =
      render(view)
      |> Floki.parse_document!()
      |> Floki.find("#notification-source [data-kind=info]")
      |> Floki.attribute("data-id")

    assert has_element?(
             view,
             "#notification-source [data-id='#{first_source_id}'][data-duration='8000']",
             "Appearance updated."
           )

    render_submit(view, "update_theme", %{"theme" => "light"})

    [second_source_id] =
      render(view)
      |> Floki.parse_document!()
      |> Floki.find("#notification-source [data-kind=info]")
      |> Floki.attribute("data-id")

    refute first_source_id == second_source_id

    assert has_element?(
             view,
             "#notification-source [data-id='#{second_source_id}'][data-duration='8000']",
             "Appearance updated."
           )

    for _ <- 1..2 do
      notifications
      |> element("#toast-group")
      |> render_hook("add_toast", %{
        kind: "info",
        message: "Appearance updated.",
        options: %{duration: 8000}
      })
    end

    assert has_element?(
             notifications,
             "#toast-group-stream > :nth-child(2)[data-duration='8000']",
             "Appearance updated."
           )

    [first_id, second_id] =
      render(notifications)
      |> Floki.parse_document!()
      |> Floki.find("#toast-group-stream > div")
      |> Floki.attribute("id")

    refute first_id == second_id

    assert has_element?(notifications, "##{first_id}")
    notifications |> element("#toast-group") |> render_hook("clear", %{id: first_id})
    refute has_element?(notifications, "##{first_id}")
    assert has_element?(notifications, "##{second_id}")

    render_submit(view, "update_theme", %{"theme" => "invalid"})
    assert has_element?(view, "#notification-source [data-kind=error][data-duration='0']")
    refute has_element?(view, "#settings-info, #settings-error")
  end

  test "connected apps are independent of the MCP integration flag", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/security")
    assert has_element?(view, "#connected-apps")

    FunWithFlags.enable(:chatgpt_integration, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/settings/security")
    assert has_element?(view, "#connected-apps")

    other_user = user_fixture()
    other_user = other_user |> User.confirm_changeset() |> Repo.update!()
    {:ok, view, _} = build_conn() |> log_in_user(other_user) |> live(~p"/settings/security")
    assert has_element?(view, "#connected-apps")

    FunWithFlags.disable(:chatgpt_integration, for_actor: user)
    {:ok, view, _} = live(conn, ~p"/settings/security")
    assert has_element?(view, "#connected-apps")
  end

  test "menu navigation mounts separate LiveViews and updates the active navigation", %{
    conn: conn
  } do
    pages = [
      {:account, ~p"/settings/account", "#update_email", ShroudWeb.AccountSettingsLive},
      {:security, ~p"/settings/security", "#update_password", ShroudWeb.SecuritySettingsLive},
      {:appearance, ~p"/settings/appearance", "#appearance-form",
       ShroudWeb.AppearanceSettingsLive},
      {:billing, ~p"/settings/billing", "#paddle-signup", ShroudWeb.BillingSettingsLive}
    ]

    for {source, source_path, _, source_module} <- pages,
        {target, target_path, selector, target_module} <- pages,
        source != target do
      {:ok, view, _} = live(conn, source_path)
      assert view.module == source_module
      assert has_element?(view, "#settings-nav-#{source}[aria-current=page]")
      next = navigate_settings(view, conn, target, target_path)
      refute next.pid == view.pid
      assert next.module == target_module
      assert has_element?(next, selector)
      assert has_element?(next, "#settings-nav-#{target}[aria-current=page]")
      refute has_element?(next, "#settings-nav-#{source}[aria-current=page]")
    end
  end

  test "connected apps appear alongside the other security settings", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings/security")
    assert view.module == ShroudWeb.SecuritySettingsLive
    assert has_element?(view, "#connected-apps #no-connections", "No connected apps")
    assert has_element?(view, "#settings-nav-security[aria-current=page]")
    assert has_element?(view, "#update_password")
    refute has_element?(view, "#manage-connections, #back-to-security")
  end

  test "settings require a confirmed, authenticated user", %{conn: conn} do
    for path <-
          ~w(/settings/account /settings/security /settings/appearance /settings/billing /settings/billing/lifetime) do
      assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(build_conn(), path)
      unconfirmed = user_fixture()

      assert {:error, {:redirect, %{to: "/users/confirm"}}} =
               conn |> log_in_user(unconfirmed) |> live(path)
    end
  end

  test "email changes send confirmation without changing the account yet", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/account")
    email = unique_user_email()

    view
    |> form("#update_email", user: %{email: email}, current_password: valid_user_password())
    |> render_submit()

    assert has_element?(
             view,
             "#notification-source [data-kind=info]",
             "A link to confirm your email"
           )

    assert Repo.reload!(user).email == user.email
    assert_receive {:email, %{to: [{_, ^email}], text_body: body}}
    assert body =~ "/settings/confirm_email/"
  end

  test "email changes reject known and unknown Shroud addresses with a generic error", %{
    conn: conn,
    user: user
  } do
    email_alias = alias_fixture(%{user_id: user.id})
    {:ok, view, _} = live(conn, ~p"/settings/account")

    for email <- [email_alias.address, "unknown@email.shroud.test"] do
      view
      |> form("#update_email", user: %{email: email}, current_password: valid_user_password())
      |> render_submit()

      assert has_element?(view, "#update_email .invalid-feedback", "is invalid")
      refute has_element?(view, "#notification-source [data-kind=info]")
      assert Repo.reload!(user).email == user.email
    end

    refute_receive {:email, _}
  end

  test "email and current-password errors are rendered in place", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/settings/account")

    view
    |> form("#update_email", user: %{email: "with spaces"}, current_password: "invalid")
    |> render_submit()

    assert has_element?(view, "#update_email .invalid-feedback", "is invalid")
    assert has_element?(view, "#update_email .invalid-feedback", "is not valid")
    assert Repo.reload!(user).email == user.email
  end

  test "invalid passwords stay in LiveView without rotating the session", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/security")

    view
    |> form("#update_password",
      user: %{password: "too short", password_confirmation: "does not match"},
      current_password: "invalid"
    )
    |> render_submit()

    assert has_element?(view, "#update_password .invalid-feedback", "should be at least 12")
    assert has_element?(view, "#update_password .invalid-feedback", "does not match password")
    assert has_element?(view, "#update_password .invalid-feedback", "is not valid")
    refute has_element?(view, "#update_password[phx-trigger-action]")
    assert Accounts.get_user_by_session_token(get_session(conn, :user_token)).id == user.id
  end

  test "valid passwords submit via HTTP to update the password and renew the session", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/security")

    password_form =
      form(view, "#update_password",
        user: %{password: "new valid password", password_confirmation: "new valid password"},
        current_password: valid_user_password()
      )

    render_submit(password_form)
    assert has_element?(view, "#update_password[phx-trigger-action]")
    new_conn = follow_trigger_action(password_form, conn)
    assert redirected_to(new_conn) == ~p"/settings/security"
    refute get_session(new_conn, :user_token) == get_session(conn, :user_token)
    refute Accounts.get_user_by_session_token(get_session(conn, :user_token))
    assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
  end

  test "themes persist and are pushed to the browser, invalid themes are rejected", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/appearance")

    for theme <- ~w(dark light system) do
      view |> form("#appearance-form", theme: theme) |> render_submit()
      assert_push_event(view, "set-theme", %{theme: theme})
      assert to_string(Repo.reload!(user).theme) == theme
      assert has_element?(view, "#appearance-form input[value=#{theme}][checked]")
    end

    render_submit(view, "update_theme", %{"theme" => "invalid"})

    assert has_element?(
             view,
             "#notification-source [data-kind=error]",
             "Invalid theme preference"
           )

    assert Repo.reload!(user).theme == :system
  end

  test "2FA enrollment verifies the generated secret and shows backup codes only once", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/security")
    view |> element("#generate_totp_secret") |> render_click()
    assert has_element?(view, "#totp-qr-code svg")
    secret = :sys.get_state(view.pid).socket.assigns.totp_secret

    view
    |> form("#enable_totp", verification_code: NimbleTOTP.verification_code(secret))
    |> render_submit()

    updated = Repo.reload!(user)
    assert updated.totp_enabled
    assert updated.totp_secret == secret
    assert length(updated.totp_backup_codes) == 8

    for code <- updated.totp_backup_codes do
      assert has_element?(view, "#totp-backup-codes .font-mono", code)
    end

    assert has_element?(view, "#copy-backup-codes[phx-hook='CopyToClipboard']")
    render_hook(view, "backup_copy_failed", %{})
    assert has_element?(view, "#backup-copy-error[role='dialog']")
    assert has_element?(view, "#backup-copy-error button[data-modal-dismiss]", "OK")
    view |> element("#backup-copy-error") |> render_hook("hide", %{})
    refute has_element?(view, "#backup-copy-error")
    assert has_element?(view, "#totp-backup-codes")

    view |> element("#dismiss-backup-codes") |> render_click()
    refute has_element?(view, "#totp-backup-codes")
    view = navigate_settings(view, conn, :account, ~p"/settings/account")
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    refute has_element?(view, "#totp-backup-codes")
    assert has_element?(view, "#show-disable-totp")
  end

  test "leaving Security discards pending 2FA enrollment and backup-code display", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/security")
    view |> element("#generate_totp_secret") |> render_click()
    secret = :sys.get_state(view.pid).socket.assigns.totp_secret

    view = navigate_settings(view, conn, :account, ~p"/settings/account")
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    refute has_element?(view, "#totp-qr-code svg")

    render_submit(view, "enable_totp", %{
      "verification_code" => NimbleTOTP.verification_code(secret)
    })

    refute Repo.reload!(user).totp_enabled

    view |> element("#generate_totp_secret") |> render_click()
    fresh_secret = :sys.get_state(view.pid).socket.assigns.totp_secret
    refute fresh_secret == secret

    view
    |> form("#enable_totp", verification_code: NimbleTOTP.verification_code(fresh_secret))
    |> render_submit()

    assert Repo.reload!(user).totp_enabled
    assert Repo.reload!(user).totp_secret == fresh_secret
    assert has_element?(view, "#totp-backup-codes")
    view = navigate_settings(view, conn, :account, ~p"/settings/account")
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    refute has_element?(view, "#totp-backup-codes")
  end

  test "invalid enrollment clears the pending secret without enabling 2FA", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/security")
    view |> element("#generate_totp_secret") |> render_click()
    view |> form("#enable_totp", verification_code: "invalid") |> render_submit()
    refute Repo.reload!(user).totp_enabled
    refute has_element?(view, "#totp-qr-code")
    assert has_element?(view, "#notification-source [data-kind=error]", "Invalid two-factor")

    view = navigate_settings(view, conn, :account, ~p"/settings/account")
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    refute has_element?(view, "#totp-qr-code")
  end

  test "2FA disable rejects invalid codes and consumes a valid backup code", %{
    conn: conn,
    user: user
  } do
    TOTP.enable_totp!(user, TOTP.create_secret())
    {:ok, view, _} = live(conn, ~p"/settings/security")
    view |> element("#show-disable-totp") |> render_click()
    view = navigate_settings(view, conn, :appearance, ~p"/settings/appearance")
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    refute has_element?(view, "#disable_totp")
    view |> element("#show-disable-totp") |> render_click()
    assert has_element?(view, "#disable_totp")
    view |> form("#disable_totp", verification_code: "invalid") |> render_submit()
    assert Repo.reload!(user).totp_enabled
    assert has_element?(view, "#notification-source [data-kind=error]", "Invalid two-factor")
    [code | remaining] = Repo.reload!(user).totp_backup_codes
    view |> form("#disable_totp", verification_code: code) |> render_submit()
    refute Repo.reload!(user).totp_enabled
    assert Repo.reload!(user).totp_backup_codes == remaining
    assert has_element?(view, "#generate_totp_secret")
    view = navigate_settings(view, conn, :account, ~p"/settings/account")
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    refute has_element?(view, "#disable_totp")
    refute has_element?(view, "#totp-qr-code")
  end

  test "lifetime redemption handles invalid and used codes, then updates billing", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/settings/billing/lifetime")
    assert view.module == ShroudWeb.BillingSettingsLive
    assert has_element?(view, "#settings-nav-billing[aria-current=page]")
    view |> form("#lifetime-form", lifetime_code: "invalid") |> render_submit()
    assert has_element?(view, "#notification-source [data-kind=error]", "Invalid code")
    refute Repo.reload!(user).status == :lifetime

    used = Billing.create_lifetime_code()
    :ok = Billing.redeem_lifetime_code(used, user_fixture())
    view |> form("#lifetime-form", lifetime_code: used) |> render_submit()
    assert has_element?(view, "#notification-source [data-kind=error]", "already been redeemed")

    code = Billing.create_lifetime_code()
    view |> form("#lifetime-form", lifetime_code: code) |> render_submit()
    assert_patch(view, ~p"/settings/billing")
    assert Repo.reload!(user).status == :lifetime
    refute has_element?(view, "#upgrade-button")
    assert has_element?(view, "#notification-source [data-kind=info]", "successfully signed up")
  end

  test "billing shows subscriber portal or free-plan upgrade", %{conn: conn, user: user} do
    user |> Ecto.Changeset.change(paddle_customer_id: "ctm_test") |> Repo.update!()
    {:ok, view, _} = live(conn, ~p"/settings/billing")
    assert has_element?(view, "a[href='/checkout/billing']")
    refute has_element?(view, "#upgrade-button")

    user |> User.status_changeset(%{status: :free}) |> Repo.update!()
    {:ok, view, _} = live(conn, ~p"/settings/billing")
    assert has_element?(view, "#paddle-signup[phx-hook=PaddleCheckout][phx-update=ignore]")
    assert has_element?(view, "#upgrade-button")
  end

  defp navigate_settings(view, conn, action, path) do
    {:ok, next, _} =
      view |> element("#settings-nav-#{action}") |> render_click() |> follow_redirect(conn, path)

    next
  end
end
