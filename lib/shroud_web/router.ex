defmodule ShroudWeb.Router do
  use ShroudWeb, :router

  import Phoenix.LiveDashboard.Router
  import ShroudWeb.UserAuth
  import ShroudWeb.UserApiAuth
  import ShroudWeb.SpamCount

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {ShroudWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
    plug(ShroudWeb.Plugs.SentryContext)
    plug(:fetch_spam_count)
  end

  pipeline :mounted_apps do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:fetch_current_user)
    plug(ShroudWeb.Plugs.SentryContext)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_current_api_user)
    plug(ShroudWeb.Plugs.SentryContext)
  end

  scope "/api", ShroudWeb do
    pipe_through(:api)

    post("/webhooks/stripe", CheckoutController, :webhook)
  end

  scope "/api/v1", ShroudWeb.Api.V1 do
    pipe_through(:api)

    post("/token", TokenController, :create)
  end

  scope "/api/v1", ShroudWeb.Api.V1 do
    pipe_through([:api, :require_confirmed_api_user])

    resources("/aliases", EmailAliasController, only: [:index, :create])
    delete("/aliases/:address", EmailAliasController, :delete)
    resources("/domains", DomainController, only: [:index])
  end

  scope "/admin" do
    pipe_through([:browser, :require_admin_user])
    live_dashboard("/", metrics: ShroudWeb.Telemetry)
  end

  scope "/feature_flags" do
    pipe_through([:mounted_apps, :require_admin_user])
    forward("/", FunWithFlags.UI.Router, namespace: "feature_flags")
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through(:browser)

      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  ## Authentication routes

  scope "/", ShroudWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    get("/users/register", UserRegistrationController, :new)
    post("/users/register", UserRegistrationController, :create)
    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
    get("/users/totp", UserSessionController, :new_totp)
    post("/users/totp", UserSessionController, :create_totp)
    get("/users/reset_password", UserResetPasswordController, :new)
    post("/users/reset_password", UserResetPasswordController, :create)
    get("/users/reset_password/:token", UserResetPasswordController, :edit)
    put("/users/reset_password/:token", UserResetPasswordController, :update)
  end

  scope "/", ShroudWeb do
    pipe_through([:browser, :require_authenticated_user, :redirect_if_user_is_confirmed])

    get("/users/confirm", UserConfirmationController, :new)
    post("/users/confirm", UserConfirmationController, :create)
  end

  scope "/", ShroudWeb do
    pipe_through([:browser, :require_admin_user])

    live_session :authenticated_admin, on_mount: ShroudWeb.AdminUserLiveAuth do
      live("/debug_emails", DebugEmailsLive.Index, :index)
      live("/debug_emails/:id", DebugEmailsLive.Show, :show)
    end
  end

  scope "/", ShroudWeb do
    pipe_through([:browser, :require_confirmed_user])

    get("/settings", UserSettingsController, :redirect_to_account)
    get("/settings/account", UserSettingsController, :account)
    get("/settings/security", UserSettingsController, :security)
    get("/settings/billing", UserSettingsController, :billing)
    get("/settings/billing/lifetime", UserSettingsController, :lifetime)
    post("/settings/billing/lifetime", UserSettingsController, :lifetime_signup)
    put("/settings", UserSettingsController, :update)
    # Route for changing email of an already-confirmed account
    get("/settings/confirm_email/:token", UserSettingsController, :confirm_email)

    live_session :authenticated, on_mount: ShroudWeb.UserLiveAuth do
      live("/", EmailAliasLive.Index, :index)
      live("/alias/:address", EmailAliasLive.Show, :show)
      live("/domains", CustomDomainLive.Index, :index)
      live("/domains/:domain", CustomDomainLive.Show, :show)
      live("/detention", SpamEmailLive.Index, :index)
    end

    get("/checkout", CheckoutController, :index)
    get("/checkout/success", CheckoutController, :success)
    get("/checkout/billing", CheckoutController, :billing_portal)
  end

  scope "/", ShroudWeb do
    pipe_through([:browser])

    get("/_health", HealthController, :show)
    delete("/users/log_out", UserSessionController, :delete)
    get("/users/confirm/:token", UserConfirmationController, :edit)
    post("/users/confirm/:token", UserConfirmationController, :update)
    get("/email-report/:data", PageController, :email_report)
    get("/proxy", ProxyController, :proxy)
  end
end
