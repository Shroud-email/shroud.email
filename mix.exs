defmodule Shroud.MixProject do
  use Mix.Project

  def project do
    [
      app: :shroud,
      version: "1.2.0",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.json": :test
      ],
      xref: [exclude: [Phoenix.VerifiedRoutes]]
    ]
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
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.7.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.9"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_live_view, "~> 0.18.3"},
      {:phoenix_live_dashboard, "~> 0.7.2"},
      {:esbuild, "~> 0.2", runtime: Mix.env() == :dev},
      {:excoveralls, "~> 0.14.3", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:sobelow, "~> 0.11.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:swoosh, "~> 1.6"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:gen_smtp, "~> 1.2"},
      {:iconv, "~> 1.0"},
      {:oban, "~> 2.9"},
      {:hackney, "~> 1.18"},
      {:ranch, "~> 1.8.0", override: true},
      {:canada, "~> 2.0"},
      {:mjml, "~> 1.1"},
      {:floki, "~> 0.33.0"},
      {:sentry, "~> 8.0"},
      {:timex, "~> 3.7"},
      {:httpoison, "~> 1.8"},
      {:quantum, "~> 3.4"},
      {:nimble_totp, "~> 0.2.0"},
      {:eqrcode, "~> 0.1.10"},
      {:cloak_ecto, "~> 1.2"},
      {:stripity_stripe, "~> 2.12"},
      {:mime, "~> 1.6.0"},
      {:scrivener_ecto, "~> 2.7"},
      {:fun_with_flags, "~> 1.8"},
      {:fun_with_flags_ui, "~> 0.8.0"},
      {:p1_utils, "~> 1.0"},
      {:ex_aws, "~> 2.3"},
      {:ex_aws_s3, "~> 2.3"},
      {:dotenv_parser, "~> 2.0", only: :dev},
      {:html_sanitize_ex, "~> 1.4"},
      {:ex_image_info, "~> 0.2.4"},
      {:ecto_psql_extras, "~> 0.7.4"},
      {:heroicons, "~> 0.5.2"}
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
      "assets.deploy": [
        "cmd --cd assets npm run deploy",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
