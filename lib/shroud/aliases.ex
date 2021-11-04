defmodule Shroud.Aliases do
  @moduledoc """
  The Aliases context.
  """

  import Ecto.Query, warn: false
  alias Shroud.Repo

  alias Shroud.Aliases.{EmailAlias, EmailMetric}

  @alias_domain Application.compile_env!(:shroud, :email_aliases)[:domain]

  def list_aliases!(user) do
    user
    |> Ecto.assoc(:aliases)
    |> where([a], is_nil(a.deleted_at))
    |> Repo.all()
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

  def increment_forwarded!(alias_id) do
    today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()

    Repo.insert!(%EmailMetric{alias_id: alias_id, date: today, forwarded: 1},
      conflict_target: [:alias_id, :date],
      on_conflict: [inc: [forwarded: 1]]
    )
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
