defmodule ShroudWeb.Router do
  use ShroudWeb, :router

  import ShroudWeb.UserAuth
  import ShroudWeb.UserApiAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ShroudWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_current_api_user
  end

  scope "/api", ShroudWeb do
    pipe_through :api

    post "/webhooks/stripe", CheckoutController, :webhook
    post "/webhooks/ohmysmtp", OhMySmtpController, :webhook
  end

  scope "/api/v1", ShroudWeb.Api.V1 do
    pipe_through :api

    post "/token", TokenController, :create
  end

  scope "/api/v1", ShroudWeb.Api.V1 do
    pipe_through [:api, :require_confirmed_api_user]

    resources "/aliases", EmailAliasController, only: [:index]
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: ShroudWeb.Telemetry
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ShroudWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/totp", UserSessionController, :new_totp
    post "/users/totp", UserSessionController, :create_totp
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", ShroudWeb do
    pipe_through [:browser, :require_authenticated_user, :redirect_if_user_is_confirmed]

    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
  end

  scope "/", ShroudWeb do
    pipe_through [:browser, :require_confirmed_user]

    get "/settings", UserSettingsController, :redirect_to_account
    get "/settings/account", UserSettingsController, :account
    get "/settings/security", UserSettingsController, :security
    get "/settings/billing", UserSettingsController, :billing
    put "/settings", UserSettingsController, :update
    # Route for changing email of an already-confirmed account
    get "/settings/confirm_email/:token", UserSettingsController, :confirm_email

    live_session :aliases, on_mount: ShroudWeb.UserLiveAuth do
      live "/", EmailAliasLive.Index, :index
      live "/alias/:address", EmailAliasLive.Show, :show
    end

    get "/checkout", CheckoutController, :index
    get "/checkout/success", CheckoutController, :success
    get "/checkout/billing", CheckoutController, :billing_portal
  end

  scope "/", ShroudWeb do
    pipe_through [:browser]

    get "/_health", HealthController, :show
    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
    get "/email-report/:data", PageController, :email_report
    get "/proxy", ProxyController, :proxy
  end
end
