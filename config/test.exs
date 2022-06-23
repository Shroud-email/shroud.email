import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :shroud, Shroud.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  database: System.get_env("POSTGRES_DB") || "shroud_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :shroud, :email_aliases, domain: "shroud.test"

config :shroud, Shroud.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("3ni2dy3ES8g2vaRvws/fZgE+nB2ZqJqcbKbrhNl1NtM="),
      iv_length: 12
    }
  ]

config :shroud, Oban, testing: :manual

config :appsignal, :config, active: false

config :shroud, :mailer,
  smtp_options: [
    port: 2526
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :shroud, ShroudWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BHTb6VLE2LA4imiaMxrkyjbHP4cfWeCc92SS7SUe/zxpV4BEs5UkyKVrQE48b9MR",
  server: false

# In test we don't send emails.
config :shroud, Shroud.Mailer, adapter: Swoosh.Adapters.Test

# We have tests for our logging, and these require a log level of at least info
config :logger, level: :notice
# But only print warnings and higher to the console
config :logger, :console, level: :warn

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :shroud,
  notifier_webhook_url: "webhook.com/webhook",
  email_octopus_list_id: 123,
  email_octopus_api_key: "deadbeef"
