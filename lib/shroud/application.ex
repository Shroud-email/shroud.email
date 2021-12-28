defmodule Shroud.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Shroud.Repo,
      # Start the Telemetry supervisor
      ShroudWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Shroud.PubSub},
      # Start the Endpoint (http/https)
      ShroudWeb.Endpoint,
      {Oban, Application.fetch_env!(:shroud, Oban)},
      # Start a worker by calling: Shroud.Worker.start_link(arg)
      # {Shroud.Worker, arg}
      {Shroud.Email.SmtpServer, Application.fetch_env!(:shroud, :mailer)[:smtp_options]},
      Shroud.Scheduler,
      Shroud.Vault,
      {Registry,
       [
         name: Appsignal.Registry,
         keys: :unique,
         partitions: System.schedulers_online()
       ]}
    ]

    {:ok, _} = Application.ensure_all_started(:appsignal)

    :telemetry.attach_many(
      "appsignal-oban",
      [
        [:oban, :job, :start],
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &Shroud.AppsignalOban.handle_event/4,
      nil
    )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Shroud.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShroudWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
