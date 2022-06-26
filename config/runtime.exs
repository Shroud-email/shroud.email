import Config

config :stripity_stripe, api_key: System.get_env("STRIPE_SECRET")

config :shroud, :billing,
  stripe_yearly_price: System.get_env("STRIPE_YEARLY_PRICE"),
  stripe_monthly_price: System.get_env("STRIPE_MONTHLY_PRICE"),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.
if config_env() == :prod do
  email_domain =
    System.get_env("EMAIL_DOMAIN") ||
      raise """
      environment variable EMAIL_DOMAIN is missing.
      For example: fog.shroud.email
      """

  config :shroud, :email_aliases, domain: email_domain

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
      host: System.get_env("APP_DOMAIN") || "app.shroud.email",
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

  config :shroud, Shroud.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_RELAY") || "localhost",
    username: smtp_username,
    password: smtp_password,
    ssl: false,
    tls: :if_available,
    auth: :always,
    retries: 5,
    no_mx_lookups: true

  config :swoosh, :api_client, Swoosh.ApiClient.Hackney

  config :appsignal, :config, push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY")

  config :shroud,
    notifier_webhook_url: System.get_env("NOTIFIER_WEBHOOK_URL"),
    email_octopus_list_id: System.get_env("EMAIL_OCTOPUS_LIST_ID"),
    email_octopus_api_key: System.get_env("EMAIL_OCTOPUS_API_KEY"),
    admin_user_email: System.get_env("ADMIN_EMAIL")
end
