defmodule Shroud.Repo do
  use Ecto.Repo,
    otp_app: :shroud,
    adapter: Ecto.Adapters.Postgres
end
