defmodule Shroud.Release do
  @app :shroud

  alias Shroud.Repo
  import Ecto.Query

  alias Shroud.Accounts
  alias Shroud.Aliases.{EmailAlias, EmailMetric}
  alias Shroud.Accounts.User
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
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      user =
        %User{}
        |> User.registration_changeset(%{email: email, password: password, status: :lifetime})
        |> Ecto.Changeset.change(%{confirmed_at: now, is_admin: true})
        |> Repo.insert!()

      Accounts.deliver_user_reset_password_instructions(
        user,
        &Routes.user_reset_password_url(ShroudWeb.Endpoint, :edit, &1)
      )
    end
  end

  def make_emails_case_insensitive do
    start_app()

    Repo.transaction(fn ->
      duplicate_aliases =
        from(a in EmailAlias,
          select: fragment("lower(?)", a.address),
          group_by: fragment("lower(?)", a.address),
          having: count("*") > 1
        )
        |> Repo.all()

      duplicate_aliases
      |> Enum.each(&handle_duplicate_alias/1)

      from(a in EmailAlias, update: [set: [address: fragment("lower(?)", a.address)]])
      |> Repo.update_all([])
    end)
  end

  defp handle_duplicate_alias(email_alias) do
    duplicates =
      Repo.all(
        from(a in EmailAlias,
          where: fragment("lower(?)", a.address) == ^email_alias,
          order_by: a.inserted_at
        )
      )

    [first | rest] = duplicates

    # Update metrics
    dates =
      Repo.all(
        from(m in EmailMetric,
          where: m.alias_id in ^Enum.map(duplicates, & &1.id),
          select: m.date
        )
      )

    Enum.each(dates, fn date ->
      metrics =
        Repo.all(
          from(m in EmailMetric,
            where: m.alias_id in ^Enum.map(duplicates, & &1.id),
            where: m.date == ^date
          )
        )

      first_metric = Repo.get_by(EmailMetric, date: date, alias_id: first.id)

      first_metric =
        if is_nil(first_metric) do
          %EmailMetric{}
          |> EmailMetric.changeset(%{date: date, alias_id: first.id})
          |> Repo.insert!()
        else
          first_metric
        end

      forwarded_sum = Enum.map(metrics, & &1.forwarded) |> Enum.sum()
      blocked_sum = Enum.map(metrics, & &1.blocked) |> Enum.sum()
      replied_sum = Enum.map(metrics, & &1.replied) |> Enum.sum()

      EmailMetric.changeset(first_metric, %{
        forwarded: forwarded_sum,
        blocked: blocked_sum,
        replied: replied_sum
      })
      |> Repo.update!()

      Repo.delete_all(from m in EmailMetric, where: m.alias_id in ^Enum.map(rest, & &1.id))
    end)

    from(m in EmailMetric,
      where: m.alias_id in ^Enum.map(rest, & &1.id)
    )
    |> Repo.update_all(set: [alias_id: first.id])

    title = duplicates |> Enum.map_join("\n", & &1.title)
    notes = duplicates |> Enum.map_join("\n", & &1.notes)

    forwarded = duplicates |> Enum.map(& &1.forwarded) |> Enum.sum()
    blocked = duplicates |> Enum.map(& &1.blocked) |> Enum.sum()
    replied = duplicates |> Enum.map(& &1.replied) |> Enum.sum()

    first =
      EmailAlias.changeset(first, %{
        title: title,
        notes: notes,
        forwarded: forwarded,
        blocked: blocked,
        replied: replied
      })

    Repo.update!(first)
    Repo.delete_all(from a in EmailAlias, where: a.id in ^Enum.map(rest, & &1.id))
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
