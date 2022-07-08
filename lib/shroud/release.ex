defmodule Shroud.Release do
  @app :shroud

  alias Shroud.Accounts
  alias ShroudWeb.Router.Helpers, as: Routes

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_admin_user do
    start_app()
    email = Application.get_env(:shroud, :admin_user_email)

    if email && is_nil(Accounts.get_user_by_email(email)) do
      # some random password, but we sent a password reset email so the user can set their own
      password = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
      {:ok, user} = Accounts.register_user(%{email: email, password: password, status: :lifetime})

      Accounts.deliver_user_confirmation_instructions(
        user,
        &Routes.user_confirmation_url(ShroudWeb.Endpoint, :edit, &1)
      )

      Accounts.deliver_user_reset_password_instructions(
        user,
        &Routes.user_reset_password_url(ShroudWeb.Endpoint, :edit, &1)
      )
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.put_env(@app, :minimal, true)
    Application.ensure_all_started(@app)
  end
end
