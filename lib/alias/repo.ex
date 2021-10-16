defmodule Alias.Repo do
  use Ecto.Repo,
    otp_app: :alias,
    adapter: Ecto.Adapters.Postgres
end
