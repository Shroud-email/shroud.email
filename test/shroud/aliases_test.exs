defmodule Shroud.AliasesTest do
  use Shroud.DataCase

  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias

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
    test "it sets deleted_at" do
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
end
