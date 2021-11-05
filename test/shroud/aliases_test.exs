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

      assert [alias_one] == Aliases.list_aliases!(user_one)
      assert [alias_two] == Aliases.list_aliases!(user_two)
    end

    test "does not include deleted aliases" do
      %{id: id} = user = user_fixture()
      email_alias = alias_fixture(%{user_id: id})
      Aliases.delete_email_alias(email_alias.id)

      assert [] == Aliases.list_aliases!(user)
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
