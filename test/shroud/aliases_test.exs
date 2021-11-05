defmodule Shroud.AliasesTest do
  use Shroud.DataCase

  alias Shroud.Aliases
  alias Shroud.Aliases.{EmailAlias, EmailMetric}

  import Shroud.{AccountsFixtures, AliasesFixtures}

  describe "list_aliases/1" do
    test "lists only the user's aliases" do
      %{id: id_one} = user_one = user_fixture()
      %{id: id_two} = user_two = user_fixture()
      alias_one = alias_fixture(%{user_id: id_one})
      alias_two = alias_fixture(%{user_id: id_two})

      assert [alias_one] == Aliases.list_aliases(user_one)
      assert [alias_two] == Aliases.list_aliases(user_two)
    end

    test "counts recently forwarded emails" do
      one_week_seconds = 7 * 24 * 60 * 60

      one_week_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(one_week_seconds, :second)
        |> NaiveDateTime.to_date()

      two_weeks_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(2 * one_week_seconds, :second)
        |> NaiveDateTime.to_date()

      %{id: user_id} = user = user_fixture()
      %{id: alias_id} = alias_fixture(%{user_id: user_id})
      metric_fixture(%{alias_id: alias_id, date: one_week_ago, forwarded: 1})
      metric_fixture(%{alias_id: alias_id, date: two_weeks_ago, forwarded: 2})

      listed_alias = user |> Aliases.list_aliases() |> hd()
      assert listed_alias.forwarded_in_last_30_days == 3
    end

    test "does not include deleted aliases" do
      %{id: id} = user = user_fixture()
      email_alias = alias_fixture(%{user_id: id})
      Aliases.delete_email_alias(email_alias.id)

      assert [] == Aliases.list_aliases(user)
    end
  end

  describe "delete_email_alias/1" do
    test "sets deleted_at" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})
      Aliases.delete_email_alias(email_alias.id)

      email_alias = Repo.get!(EmailAlias, email_alias.id)
      {deleted_at, _} = NaiveDateTime.to_gregorian_seconds(email_alias.deleted_at)
      {now, _} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()

      assert email_alias.deleted_at != nil
      assert_in_delta deleted_at, now, 1
    end
  end

  describe "increment_forwarded!/1" do
    test "creates a new row for the date" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})

      Aliases.increment_forwarded!(email_alias)

      metric = Repo.get_by!(EmailMetric, alias_id: email_alias.id)
      today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()
      assert metric.date == today
      assert metric.forwarded == 1
    end

    test "increments an existing row" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})
      today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()
      Repo.insert!(%EmailMetric{alias_id: email_alias.id, date: today, forwarded: 1})

      Aliases.increment_forwarded!(email_alias)

      metric = Repo.get_by!(EmailMetric, alias_id: email_alias.id)
      assert metric.forwarded == 2
    end

    test "increments forwarded field on the alias" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})

      Aliases.increment_forwarded!(email_alias)

      email_alias = Repo.reload(email_alias)
      assert email_alias.forwarded == 1
    end
  end
end
