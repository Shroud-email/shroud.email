defmodule Shroud.Aliases do
  @moduledoc """
  The Aliases context.
  """

  import Ecto.Query, warn: false
  alias Shroud.Repo

  alias Shroud.Aliases.{EmailAlias, EmailMetric}
  alias Shroud.Accounts.User

  @alias_domain Application.compile_env!(:shroud, :email_aliases)[:domain]

  @spec list_aliases(User.t()) :: [EmailAlias.t()]
  def list_aliases(%User{} = user) do
    today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()

    recent_metrics =
      from m in EmailMetric,
        where: m.date > date_add(^today, -30, "day"),
        group_by: m.alias_id,
        select: %{forwarded: sum(m.forwarded), alias_id: m.alias_id}

    query =
      from ea in EmailAlias,
        where: ea.user_id == ^user.id and is_nil(ea.deleted_at),
        left_join: m in subquery(recent_metrics),
        on: m.alias_id == ea.id,
        select_merge: %{ea | forwarded_in_last_30_days: coalesce(m.forwarded, 0)}

    Repo.all(query)
  end

  def create_email_alias(attrs) do
    %EmailAlias{}
    |> EmailAlias.changeset(attrs)
    |> Repo.insert()
  end

  def get_email_alias!(id) do
    Repo.get!(EmailAlias, id)
  end

  def get_email_alias_by_address!(address) do
    Repo.get_by!(EmailAlias, address: address)
  end

  def change_email_alias(%EmailAlias{} = email_alias, attrs \\ %{}) do
    email_alias
    |> EmailAlias.changeset(attrs)
  end

  def update_email_alias(%EmailAlias{} = email_alias, attrs) do
    change_email_alias(email_alias, attrs)
    |> Repo.update()
  end

  def create_random_email_alias(user) do
    email_alias = %{
      user_id: user.id,
      address: generate_email_address()
    }

    create_email_alias(email_alias)
  end

  def delete_email_alias(id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    get_email_alias!(id)
    |> EmailAlias.changeset(%{deleted_at: now})
    |> Repo.update()
  end

  def increment_forwarded!(%EmailAlias{} = email_alias) do
    today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()

    Repo.transaction(fn ->
      Repo.insert!(%EmailMetric{alias_id: email_alias.id, date: today, forwarded: 1},
        conflict_target: [:alias_id, :date],
        on_conflict: [inc: [forwarded: 1]]
      )

      alias_update =
        from e in EmailAlias,
          where: e.id == ^email_alias.id,
          select: e.forwarded,
          update: [inc: [forwarded: 1]]

      {1, _} = Repo.update_all(alias_update, [])
    end)
  end

  defp generate_email_address() do
    alphabet = "abcdefghijklmnopqrstuvwxyz1234567890" |> String.split("")

    address =
      Enum.reduce(1..16, [], fn _, acc -> [Enum.random(alphabet) | acc] end) |> Enum.join("")

    address = address <> "@" <> @alias_domain

    if Repo.exists?(from a in EmailAlias, where: a.address == ^address) do
      generate_email_address()
    else
      address
    end
  end
end
