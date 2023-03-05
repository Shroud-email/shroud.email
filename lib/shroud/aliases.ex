defmodule Shroud.Aliases do
  @moduledoc """
  The Aliases context.
  """

  import Ecto.Query, warn: false
  alias Shroud.Repo

  alias Shroud.Util
  alias Shroud.Domain.CustomDomain
  alias Shroud.Accounts
  alias Shroud.Aliases.{EmailAlias, EmailMetric}
  alias Shroud.Accounts.User

  @spec list_aliases(User.t()) :: [EmailAlias.t()]
  def list_aliases(%User{} = user, search_query \\ nil) do
    query =
      from(ea in EmailAlias,
        where: ea.user_id == ^user.id and is_nil(ea.deleted_at),
        left_join: m in subquery(recent_metrics()),
        on: m.alias_id == ea.id,
        select_merge: %{ea | forwarded_in_last_30_days: coalesce(m.forwarded, 0)},
        order_by: [desc: ea.inserted_at]
      )

    query =
      if is_nil(search_query) or search_query == "" do
        query
      else
        filter_aliases(search_query, query)
      end

    Repo.all(query)
  end

  @spec create_email_alias(map()) ::
          {:ok, EmailAlias.t()} | {:error, :inactive_user | :trial_limit_reached}
  def create_email_alias(attrs) do
    user = Repo.get(User, attrs.user_id)

    cond do
      user.status == :trial and
          Repo.aggregate(from(ea in EmailAlias, where: ea.user_id == ^attrs.user_id), :count) >=
            10 ->
        {:error, :trial_limit_reached}

      Accounts.active?(user) ->
        insert_email_alias(attrs)

      true ->
        {:error, :inactive_user}
    end
  end

  def get_email_alias!(id) do
    Repo.get!(EmailAlias, id)
  end

  def get_email_alias_by_address(address) do
    query =
      from(ea in EmailAlias,
        where: ea.address == ^address and is_nil(ea.deleted_at),
        left_join: m in subquery(recent_metrics()),
        on: m.alias_id == ea.id,
        select_merge: %{ea | forwarded_in_last_30_days: coalesce(m.forwarded, 0)}
      )

    Repo.one(query)
  end

  def get_email_alias_by_address!(address) do
    query =
      from(ea in EmailAlias,
        where: ea.address == ^address and is_nil(ea.deleted_at),
        left_join: m in subquery(recent_metrics()),
        on: m.alias_id == ea.id,
        select_merge: %{
          forwarded_in_last_30_days: coalesce(m.forwarded, 0),
          blocked_in_last_30_days: coalesce(m.blocked, 0),
          replied_in_last_30_days: coalesce(m.replied, 0)
        }
      )

    Repo.one!(query)
  end

  def change_email_alias(%EmailAlias{} = email_alias, attrs \\ %{}) do
    email_alias
    |> EmailAlias.changeset(attrs)
  end

  def update_email_alias(%EmailAlias{} = email_alias, attrs) do
    change_email_alias(email_alias, attrs)
    |> Repo.update()
  end

  @spec block_sender(EmailAlias.t(), String.t()) ::
          {:ok, EmailAlias.t()} | {:error, Ecto.Changeset.t()}
  def block_sender(%EmailAlias{} = email_alias, sender) do
    blocked_addresses = MapSet.new([String.downcase(sender) | email_alias.blocked_addresses])
    attrs = %{blocked_addresses: MapSet.to_list(blocked_addresses)}

    email_alias
    |> EmailAlias.blocked_addresses_changeset(attrs)
    |> Repo.update()
  end

  @spec unblock_sender(EmailAlias.t(), String.t()) :: {:ok, EmailAlias.t()} | :error
  def unblock_sender(%EmailAlias{} = email_alias, sender) do
    blocked_addresses =
      email_alias.blocked_addresses
      |> Enum.map(&String.downcase/1)
      |> Enum.reject(fn address -> address == String.downcase(sender) end)

    attrs = %{blocked_addresses: blocked_addresses}

    email_alias
    |> EmailAlias.blocked_addresses_changeset(attrs)
    |> Repo.update()
  end

  def create_random_email_alias(user, attrs \\ %{}) do
    %{
      user_id: user.id,
      address: generate_email_address()
    }
    |> Map.merge(attrs)
    |> create_email_alias()
  end

  @doc """
  Deletes an email alias. If it's on a custom domain, it gets hard deleted.
  If not, it gets soft deleted to prevent other users from using it in the future.
  (Presumably, if it's on a custom domain, the user is the owner of the domain)
  """
  def delete_email_alias(id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    email_alias = get_email_alias!(id)

    if is_nil(email_alias.domain_id) do
      email_alias
      |> EmailAlias.changeset(%{deleted_at: now})
      |> Repo.update()
    else
      Repo.delete(email_alias)
    end
  end

  def increment_forwarded!(%EmailAlias{} = email_alias) do
    today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()

    Repo.transaction(fn ->
      Repo.insert!(%EmailMetric{alias_id: email_alias.id, date: today, forwarded: 1},
        conflict_target: [:alias_id, :date],
        on_conflict: [inc: [forwarded: 1]]
      )

      alias_update =
        from(e in EmailAlias,
          where: e.id == ^email_alias.id,
          select: e.forwarded,
          update: [inc: [forwarded: 1]]
        )

      {1, _} = Repo.update_all(alias_update, [])
    end)
  end

  def increment_blocked!(%EmailAlias{} = email_alias) do
    today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()

    Repo.transaction(fn ->
      Repo.insert!(%EmailMetric{alias_id: email_alias.id, date: today, blocked: 1},
        conflict_target: [:alias_id, :date],
        on_conflict: [inc: [blocked: 1]]
      )

      alias_update =
        from(e in EmailAlias,
          where: e.id == ^email_alias.id,
          select: e.blocked,
          update: [inc: [blocked: 1]]
        )

      {1, _} = Repo.update_all(alias_update, [])
    end)
  end

  def increment_replied!(%EmailAlias{} = email_alias) do
    today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()

    Repo.transaction(fn ->
      Repo.insert!(%EmailMetric{alias_id: email_alias.id, date: today, replied: 1},
        conflict_target: [:alias_id, :date],
        on_conflict: [inc: [replied: 1]]
      )

      alias_update =
        from(e in EmailAlias,
          where: e.id == ^email_alias.id,
          select: e.replied,
          update: [inc: [replied: 1]]
        )

      {1, _} = Repo.update_all(alias_update, [])
    end)
  end

  defp generate_email_address() do
    # Note: don't ever use underscores in an alias as it will break Shroud.Email.ReplyAddress.
    alphabet = "abcdefghijklmnopqrstuvwxyz1234567890" |> String.split("")

    address =
      Enum.reduce(1..16, [], fn _, acc -> [Enum.random(alphabet) | acc] end) |> Enum.join("")

    address = address <> "@" <> Util.email_domain()

    if Repo.exists?(from(a in EmailAlias, where: a.address == ^address)) do
      generate_email_address()
    else
      address
    end
  end

  defp recent_metrics do
    today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()

    from(m in EmailMetric,
      where: m.date > date_add(^today, -30, "day"),
      group_by: m.alias_id,
      select: %{
        forwarded: sum(m.forwarded),
        blocked: sum(m.blocked),
        replied: sum(m.replied),
        alias_id: m.alias_id
      }
    )
  end

  # Shamelessly copied from https://smartlogic.io/blog/dynamic-conditionals-with-ecto/
  defp filter_aliases(value, query) do
    # value is the string entered by the user
    # query is the existing database query with prior scopes applied
    values =
      value
      # split on and remove all extra whitespace
      |> String.split(~r/ +/, trim: true)
      |> Enum.map(fn value ->
        # replace non characters with wildcard characters
        "%" <> String.replace(value, ~r/[\b\W]+/, "%") <> "%"
      end)

    conditions =
      values
      |> Enum.reduce(false, fn v, acc_query ->
        dynamic(
          [ea],
          ilike(ea.address, ^v) or ilike(ea.title, ^v) or ilike(ea.notes, ^v) or ^acc_query
        )
      end)

    query
    |> where(^conditions)
  end

  defp insert_email_alias(attrs) do
    {_local, domain} = Util.extract_email_parts(attrs.address)

    custom_domain = Repo.get_by(CustomDomain, domain: domain)

    domain_id =
      if is_nil(custom_domain) do
        nil
      else
        custom_domain.id
      end

    attrs = Map.merge(attrs, %{domain_id: domain_id})

    %EmailAlias{}
    |> EmailAlias.changeset(attrs)
    |> Repo.insert()
  end
end
