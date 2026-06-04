defmodule Shroud.MixProject do
  use Mix.Project

  def project do
    [
      app: :shroud,
      version: "1.2.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [preferred_envs: [coveralls: :test, "coveralls.json": :test]]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Shroud.Application, []},
      extra_applications: [:logger, :runtime_tools, :p1_utils, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.3"},
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1.28"},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:excoveralls, "~> 0.14.3", only: :test},
      {:lazy_html, ">= 0.0.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:sobelow, "~> 0.11.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:swoosh, "~> 1.25"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.7"},
      {:gen_smtp, "~> 1.3"},
      {:iconv, "~> 1.0"},
      {:oban, "~> 2.9"},
      {:hackney, "~> 1.18"},
      {:ranch, "~> 1.8.0", override: true},
      {:canada, "~> 2.0"},
      {:mjml, "~> 6.0"},
      {:floki, "~> 0.38"},
      {:sentry, "~> 13.0"},
      # Sentry 13's default HTTP client (Sentry.FinchClient) requires Finch;
      # the legacy Sentry.HackneyClient is deprecated. Sentry manages its own
      # Finch pool, so no extra supervision is needed.
      {:finch, "~> 0.22"},
      {:timex, "~> 3.7"},
      {:httpoison, "~> 2.3"},
      {:quantum, "~> 3.4"},
      {:nimble_totp, "~> 0.2.0"},
      {:eqrcode, "~> 0.2.0"},
      {:cloak_ecto, "~> 1.2"},
      # Pinned below 3.3: stripity_stripe 3.3+ requires hackney ~> 4.0, which
      # conflicts with httpoison's hackney ~> 1.21. Reaching 3.3+ means dropping
      # httpoison (or migrating it off hackney 1.x) — deferred with the hackney
      # major upgrade.
      {:stripity_stripe, "~> 3.0 and < 3.3.0"},
      {:mime, "~> 2.0"},
      {:scrivener_ecto, "~> 3.1"},
      {:fun_with_flags, "~> 1.13"},
      {:fun_with_flags_ui, "~> 0.8.0"},
      {:p1_utils, "~> 1.0"},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_s3, "~> 2.5"},
      {:dotenv_parser, "~> 2.0", only: :dev},
      {:html_sanitize_ex, "~> 1.5"},
      {:ex_image_info, "~> 0.2.4"},
      {:ecto_psql_extras, "~> 0.8.8"},
      {:heroicons, "~> 0.5.7"},
      {:mailex, "~> 0.1.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.seed": ["run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.deploy": [
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
