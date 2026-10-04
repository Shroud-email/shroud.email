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
    plug(:put_root_layout, html: {ShroudWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
    plug(ShroudWeb.Plugs.RateLimit, :routes)
    plug(ShroudWeb.Plugs.SentryContext)
    plug(:fetch_spam_count)
  end

  pipeline :mounted_apps do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:fetch_current_user)
    plug(ShroudWeb.Plugs.RateLimit, :routes)
    plug(ShroudWeb.Plugs.SentryContext)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_current_api_user)
    plug(ShroudWeb.Plugs.RateLimit, :routes)
    plug(ShroudWeb.Plugs.SentryContext)
  end

  pipeline :mcp do
    plug(ShroudWeb.Plugs.McpAuth)
  end

  scope "/", ShroudWeb do
    get("/.well-known/oauth-authorization-server", McpOAuthController, :metadata)
    get("/.well-known/oauth-protected-resource", McpOAuthController, :resource_metadata)
    get("/.well-known/oauth-protected-resource/mcp", McpOAuthController, :resource_metadata)
    get("/.well-known/oauth-protected-resource/api/v1", McpOAuthController, :resource_metadata)
    get("/.well-known/apple-app-site-association", MobileAssociationController, :apple)
    get("/.well-known/assetlinks.json", MobileAssociationController, :android)
    get("/oauth/callback", McpOAuthController, :callback_fallback)
    post("/oauth/register", McpOAuthController, :register)
    post("/oauth/token", McpOAuthController, :token)
    post("/oauth/revoke", McpOAuthController, :revoke)
  end

  scope "/", ShroudWeb do
    pipe_through([:browser, :require_confirmed_user])
    get("/oauth/authorize", McpOAuthController, :authorize)
    post("/oauth/authorize", McpOAuthController, :consent)
  end

  scope "/" do
    pipe_through(:mcp)

    forward("/mcp", ExMCP.HttpPlug,
      handler: ShroudWeb.McpHandler,
      handler_opts: {ShroudWeb.Plugs.McpAuth, :handler_opts, []},
      protocol_mode: :prefer_modern,
      validate_origin: false,
      body_limit: 65_536,
      handler_call_timeout: 5_000,
      server_info: %{name: "shroud-email", version: "1.0.0"},
      server_capabilities: %{tools: %{listChanged: false}}
    )
  end

  scope "/api", ShroudWeb do
    pipe_through(:api)

    post("/webhooks/paddle", CheckoutController, :webhook)
  end

  scope "/api/v1", ShroudWeb.Api.V1 do
    pipe_through(:api)

    post("/token", TokenController, :create)
  end

  scope "/api/v1", ShroudWeb.Api.V1 do
    pipe_through([:api, :require_confirmed_api_user])

    get("/me", ProfileController, :show)
    resources("/aliases", EmailAliasController, only: [:index, :create])
    get("/aliases/:address", EmailAliasController, :show)
    patch("/aliases/:address", EmailAliasController, :update)
    delete("/aliases/:address", EmailAliasController, :delete)
    resources("/domains", DomainController, only: [:index])
  end

  scope "/admin", ShroudWeb do
    pipe_through([:browser, :require_admin_user])

    live_session :mailserver_admin, on_mount: ShroudWeb.AdminUserLiveAuth do
      live("/mailserver", MailserverHealthLive.Index, :index)
    end

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
    post("/users/passkeys", PasskeySessionController, :create)
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
    put("/settings/password", UserSettingsController, :update_password)
    # Route for changing email of an already-confirmed account
    get("/settings/confirm_email/:token", UserSettingsController, :confirm_email)

    live_session :authenticated, on_mount: ShroudWeb.UserLiveAuth do
      live("/settings/account", UserSettingsLive, :account)
      live("/settings/security", UserSettingsLive, :security)
      live("/settings/connections", UserSettingsLive, :connections)
      live("/settings/appearance", UserSettingsLive, :appearance)
      live("/settings/billing", UserSettingsLive, :billing)
      live("/settings/billing/lifetime", UserSettingsLive, :lifetime)
      live("/", EmailAliasLive.Index, :index)
      live("/alias/:address", EmailAliasLive.Show, :show)
      live("/domains", CustomDomainLive.Index, :index)
      live("/domains/:domain", CustomDomainLive.Show, :show)
      live("/detention", SpamEmailLive.Index, :index)
    end

    get("/checkout/billing", CheckoutController, :billing_portal)
    post("/checkout/paddle", CheckoutController, :create)
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
