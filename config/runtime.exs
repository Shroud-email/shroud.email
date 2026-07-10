import Config

if Config.config_env() == :dev do
  DotenvParser.load_file(".env")
end

# Optional: Chatwoot support widget. Set CHATWOOT_BASE_URL to the URL of
# your Chatwoot server to enable the widget. When unset (e.g. for
# self-hosted deployments), the widget is not loaded at all.
# CHATWOOT_HMAC_TOKEN is an optional secret for identity validation.
config :shroud,
  chatwoot_base_url: System.get_env("CHATWOOT_BASE_URL"),
  chatwoot_hmac_token: System.get_env("CHATWOOT_HMAC_TOKEN")

# Optional: Cap CAPTCHA. Set all three of CAP_INSTANCE_URL, CAP_SITE_KEY,
# and CAP_SECRET_KEY to enable. When any is unset, Cap is fully disabled
# (no widget rendered, no verification performed). The instance URL is
# the Cap Standalone base, e.g. http://cap:3000 (in compose) or
# https://cap.yourdomain.com.
config :shroud,
  cap_instance_url: System.get_env("CAP_INSTANCE_URL"),
  cap_site_key: System.get_env("CAP_SITE_KEY"),
  cap_secret_key: System.get_env("CAP_SECRET_KEY")

# In the test env, billing config (incl. a fixed webhook secret) comes from
# config/test.exs instead of these env vars.
if config_env() != :test do
  config :shroud, :billing,
    paddle_api_key: System.fetch_env!("PADDLE_API_KEY"),
    paddle_webhook_secret: System.fetch_env!("PADDLE_WEBHOOK_SECRET"),
    paddle_yearly_price_id: System.fetch_env!("PADDLE_YEARLY_PRICE_ID"),
    paddle_base_url: System.get_env("PADDLE_BASE_URL") || "https://api.paddle.com",
    paddle_client_token: System.fetch_env!("PADDLE_CLIENT_TOKEN"),
    paddle_environment: System.get_env("PADDLE_ENVIRONMENT") || "live"
end

# ex_aws configured with AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
# environment variables in addition to this one
s3_bucket = System.get_env("S3_BUCKET") || "shroud-email"
s3_host = System.get_env("S3_HOST") || "s3.amazonaws.com"
config :shroud, :bounces, s3_bucket: s3_bucket

config :ex_aws,
  s3: [
    scheme: "https",
    host: s3_host
  ]

config :shroud,
  loops_api_key: System.get_env("LOOPS_API_KEY"),
  loops_active_users_list_id: System.get_env("LOOPS_ACTIVE_USERS_LIST_ID")

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.
if config_env() == :prod do
  app_domain =
    System.get_env("APP_DOMAIN") ||
      raise """
      environment variable APP_DOMAIN is missing.
      For example: app.shroud.email
      """

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :shroud, Shroud.Repo,
    # ssl: true,
    # socket_options: [:inet6],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  vault_key =
    System.get_env("DB_ENCRYPTION_KEY") ||
      raise """
      environment variable DB_ENCRYPTION_KEY is missing.
      """

  config :shroud, Shroud.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: vault_key |> Base.decode64!(), iv_length: 12
      }
    ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :shroud, ShroudWeb.Endpoint,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    url: [
      host: app_domain,
      port: 443,
      scheme: "https"
    ],
    secret_key_base: secret_key_base,
    server: true

  # ## Configuring the mailer
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  smtp_username =
    System.get_env("SMTP_USERNAME") || raise "environment variable SMTP_USERNAME is missing"

  smtp_password =
    System.get_env("SMTP_PASSWORD") || raise "environment variable SMTP_PASSWORD is missing"

  smtp_relay = System.get_env("SMTP_RELAY") || "localhost"

  smtp_port = String.to_integer(System.get_env("SMTP_PORT") || "25")

  smtp_tls =
    case System.get_env("SMTP_TLS", "always") do
      "always" -> :always
      "if_available" -> :if_available
      "never" -> :never
      value -> raise "invalid SMTP_TLS value: #{inspect(value)}"
    end

  smtp_auth =
    case System.get_env("SMTP_AUTH", "always") do
      "always" -> :always
      "if_available" -> :if_available
      "never" -> :never
      value -> raise "invalid SMTP_AUTH value: #{inspect(value)}"
    end

  config :shroud, Shroud.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    username: smtp_username,
    password: smtp_password,
    ssl: false,
    tls: smtp_tls,
    auth: smtp_auth,
    port: smtp_port,
    retries: 5,
    no_mx_lookups: true,
    tls_options: [
      verify: :verify_none
    ]

  config :swoosh, :api_client, Swoosh.ApiClient.Hackney

  email_domain =
    System.get_env("EMAIL_DOMAIN") ||
      raise """
      environment variable EMAIL_DOMAIN is missing.
      For example: fog.shroud.email
      """

  config :shroud,
    notifier_webhook_url: System.get_env("NOTIFIER_WEBHOOK_URL"),
    admin_user_email: System.get_env("ADMIN_EMAIL"),
    disable_signups: System.get_env("DISABLE_SIGNUPS") in ~w(true 1 yes),
    app_domain: app_domain,
    email_domain: email_domain,
    env: :prod

  # Sentry error reporting. SENTRY_RELEASE is baked into the image at build
  # time (see Dockerfile).
  if sentry_dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: config_env(),
      release: System.get_env("SENTRY_RELEASE"),
      integrations: [
        oban: [
          capture_errors: true,
          cron: [enabled: true]
        ]
      ]
  end
end
