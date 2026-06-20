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
    formats: [html: ShroudWeb.ErrorHTML, json: ShroudWeb.ErrorJSON],
    layout: false
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
  tracker_list_uri: "https://trackers.shroud.email/list.txt",
  disable_signups: false

config :shroud, Shroud.Scheduler,
  jobs: [
    # Daily at midnight
    {"@daily", {Shroud.Scheduler, :update_trackers, []}},
    {"@hourly", {Shroud.Scheduler, :delete_spam_emails, []}},
    {"@hourly", {Shroud.Scheduler, :verify_custom_domains, []}}
  ]

config :swoosh, :api_client, Swoosh.ApiClient.Hackney

config :shroud, Oban,
  repo: Shroud.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [
    default: 1,
    outgoing_email: 5,
    notifier: 1,
    dns_checker: 3
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.24.2",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --loader:.ttf=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.2.4",
  default: [
    args: ~w(--input=css/app.css --output=../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
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

# Charsets that mailex (via codepagex) should transcode to UTF-8 when decoding
# incoming emails. codepagex only compiles the ISO-8859 family by default, and
# setting :encodings replaces that default, so ISO-8859 is re-listed here
# alongside the Windows codepages. After changing this list, run
# `mix deps.compile codepagex --force`.
config :codepagex, :encodings, [
  "ISO8859/8859-1",
  "ISO8859/8859-2",
  "ISO8859/8859-3",
  "ISO8859/8859-4",
  "ISO8859/8859-5",
  "ISO8859/8859-6",
  "ISO8859/8859-7",
  "ISO8859/8859-8",
  "ISO8859/8859-9",
  "ISO8859/8859-10",
  "ISO8859/8859-11",
  "ISO8859/8859-13",
  "ISO8859/8859-14",
  "ISO8859/8859-15",
  "ISO8859/8859-16",
  "VENDORS/MICSFT/WINDOWS/CP1250",
  "VENDORS/MICSFT/WINDOWS/CP1251",
  "VENDORS/MICSFT/WINDOWS/CP1252",
  "VENDORS/MICSFT/WINDOWS/CP1253",
  "VENDORS/MICSFT/WINDOWS/CP1254",
  "VENDORS/MICSFT/WINDOWS/CP1255",
  "VENDORS/MICSFT/WINDOWS/CP1256",
  "VENDORS/MICSFT/WINDOWS/CP1257",
  "VENDORS/MICSFT/WINDOWS/CP1258"
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
