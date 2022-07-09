import Config

config :appsignal, :config,
  otp_app: :shroud,
  name: "shroud",
  env: Mix.env(),
  ignore_actions: ["ShroudWeb.HealthController#show"]
