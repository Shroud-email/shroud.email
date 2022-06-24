# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :shroud,
  ecto_repos: [Shroud.Repo]

# Configures the endpoint
config :shroud, ShroudWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    view: ShroudWeb.ErrorView,
    accepts: ~w(html json),
    layout: {ShroudWeb.LayoutView, "error.html"}
  ],
  pubsub_server: Shroud.PubSub,
  live_view: [signing_salt: "OFJWqfW8"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :shroud, Shroud.Mailer, adapter: Swoosh.Adapters.Local

config :shroud, :mailer,
  smtp_options: [
    port: 1587,
    sessionoptions: [hostname: "shroud.email.local"],
    tls_options: [
      # Don't verify peers (we'll forward anything we can)
      verify: :verify_none,
      log_level: :debug
    ]
  ]

config :shroud,
  http_client: HTTPoison,
  tracker_list_uri: "https://raw.githubusercontent.com/Shroud-email/email-trackers/main/list.txt"

config :shroud, Shroud.Scheduler,
  jobs: [
    # Daily at midnight
    {"@daily", {Shroud.Scheduler, :update_trackers, []}},
    {"@daily", {Shroud.Scheduler, :email_expiring_trials, []}},
    {"@daily", {Shroud.Scheduler, :email_expired_trials, []}}
  ]

config :swoosh, :api_client, Swoosh.ApiClient.Hackney

config :shroud, Oban,
  repo: Shroud.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 1, outgoing_email: 5, notifier: 1]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.12.18",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --loader:.ttf=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :fun_with_flags, :cache,
  enabled: true,
  # in seconds
  ttl: 120

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Shroud.Repo

config :fun_with_flags, :cache_bust_notifications, enabled: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

import_config "appsignal.exs"
