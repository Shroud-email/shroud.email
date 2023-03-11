defmodule Shroud.AliasesTest do
  use Shroud.DataCase

  alias Shroud.Aliases
  alias Shroud.Aliases.{EmailAlias, EmailMetric}

  import Shroud.{AccountsFixtures, AliasesFixtures, DomainFixtures}

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

    test "filters by query matching address" do
      %{id: id} = user = user_fixture()
      matching_alias = alias_fixture(%{user_id: id, address: "email-LOREM@example.com"})
      _other_alias = alias_fixture(%{user_id: id, address: "email-ipsum@example.com"})

      assert [matching_alias] == Aliases.list_aliases(user, "lorem")
    end

    test "filters by query matching title" do
      %{id: id} = user = user_fixture()
      matching_alias = alias_fixture(%{user_id: id, title: "Lorem ipsum"})
      _other_alias = alias_fixture(%{user_id: id, title: "dolor sit amet"})

      assert [matching_alias] == Aliases.list_aliases(user, "Ipsum")
    end

    test "filters by query matching notes" do
      %{id: id} = user = user_fixture()
      matching_alias = alias_fixture(%{user_id: id, notes: "lorem ipsum"})
      _other_alias = alias_fixture(%{user_id: id, notes: "dolor sit amet"})

      assert [matching_alias] == Aliases.list_aliases(user, "Lorem")
    end

    test "does not filter when passed empty string" do
      %{id: id} = user = user_fixture()
      email_alias = alias_fixture(%{user_id: id})

      assert [email_alias] == Aliases.list_aliases(user, "")
    end
  end

  describe "get_email_alias_by_address!/1" do
    test "counts recent metrics" do
      one_week_seconds = 7 * 24 * 60 * 60

      one_week_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(one_week_seconds, :second)
        |> NaiveDateTime.to_date()

      two_weeks_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(2 * one_week_seconds, :second)
        |> NaiveDateTime.to_date()

      %{id: user_id} = user_fixture()
      %{id: alias_id, address: alias_address} = alias_fixture(%{user_id: user_id})

      metric_fixture(%{
        alias_id: alias_id,
        date: one_week_ago,
        forwarded: 1,
        blocked: 2,
        replied: 3
      })

      metric_fixture(%{
        alias_id: alias_id,
        date: two_weeks_ago,
        forwarded: 1,
        blocked: 2,
        replied: 3
      })

      returned_alias = Aliases.get_email_alias_by_address!(alias_address)
      assert returned_alias.id == alias_id
      assert returned_alias.forwarded_in_last_30_days == 2
      assert returned_alias.blocked_in_last_30_days == 4
      assert returned_alias.replied_in_last_30_days == 6
    end

    test "does not return a deleted alias" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})
      Aliases.delete_email_alias(email_alias.id)

      assert_raise Ecto.NoResultsError,
                   ~r/expected at least one result but got none in query/,
                   fn ->
                     Aliases.get_email_alias_by_address!(email_alias.address)
                   end
    end
  end

  describe "block_sender/2" do
    test "blocks a sender" do
      %{id: user_id} = user_fixture()
      email_alias = alias_fixture(%{user_id: user_id})

      {:ok, email_alias} = Aliases.block_sender(email_alias, "test@test.com")

      assert length(email_alias.blocked_addresses) == 1
      assert hd(email_alias.blocked_addresses) == "test@test.com"
    end

    test "doesn't add duplicates" do
      %{id: user_id} = user_fixture()
      email_alias = alias_fixture(%{user_id: user_id})

      {:ok, _email_alias} = Aliases.block_sender(email_alias, "test@test.com")
      {:ok, email_alias} = Aliases.block_sender(email_alias, "test@test.com")

      assert length(email_alias.blocked_addresses) == 1
      assert hd(email_alias.blocked_addresses) == "test@test.com"
    end

    test "downcases addresses" do
      %{id: user_id} = user_fixture()
      email_alias = alias_fixture(%{user_id: user_id})

      {:ok, email_alias} = Aliases.block_sender(email_alias, "TEST@test.com")

      assert length(email_alias.blocked_addresses) == 1
      assert hd(email_alias.blocked_addresses) == "test@test.com"
    end
  end

  describe "unblock_sender/2" do
    test "unblocks a sender" do
      %{id: user_id} = user_fixture()
      email_alias = alias_fixture(%{user_id: user_id, blocked_addresses: ["test@test.com"]})

      {:ok, email_alias} = Aliases.unblock_sender(email_alias, "test@test.com")

      assert Enum.empty?(email_alias.blocked_addresses)
    end
  end

  describe "create_email_alias/1" do
    test "does not allow creating the same alias with different cases" do
      %{id: user_id} = user_fixture()

      {:ok, _email_alias} =
        Aliases.create_email_alias(%{user_id: user_id, address: "alias@random.com"})

      {:error, _error} =
        Aliases.create_email_alias(%{user_id: user_id, address: "ALIAS@random.com"})
    end

    test "saves the lowercase version of the alias" do
      %{id: user_id} = user_fixture()

      {:ok, email_alias} =
        Aliases.create_email_alias(%{user_id: user_id, address: "ALIAS@random.com"})

      assert email_alias.address == "alias@random.com"
    end

    test "does not sets a domain_id if domain doesn't exist" do
      %{id: user_id} = user_fixture()
      custom_domain_fixture(%{user_id: user_id})
      attrs = %{user_id: user_id, address: "alias@random.com"}

      {:ok, email_alias} = Aliases.create_email_alias(attrs)

      assert is_nil(email_alias.domain_id)
    end

    test "sets domain_id if one is present" do
      %{id: user_id} = user_fixture()
      %{id: domain_id, domain: domain} = custom_domain_fixture(%{user_id: user_id})
      attrs = %{user_id: user_id, address: "alias@#{domain}"}

      {:ok, email_alias} = Aliases.create_email_alias(attrs)

      assert email_alias.domain_id == domain_id
    end

    test "does not allow inactive users to create" do
      %{id: user_id} = user_fixture(%{status: :inactive})

      {:error, :inactive_user} =
        Aliases.create_email_alias(%{user_id: user_id, address: "foo@email.com"})
    end

    test "does not allow lead users to create" do
      %{id: user_id} = user_fixture(%{status: :lead})

      {:error, :inactive_user} =
        Aliases.create_email_alias(%{user_id: user_id, address: "foo@email.com"})
    end

    test "lets a trial user create an alias" do
      tomorrow = NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :day)
      %{id: user_id} = user_fixture(%{status: :trial, trial_expires_at: tomorrow})

      {:ok, _email_alias} =
        Aliases.create_email_alias(%{user_id: user_id, address: "foo@email.com"})
    end

    test "does not let an expired trial user create an alias" do
      yesterday = NaiveDateTime.utc_now() |> NaiveDateTime.add(-1, :day)
      %{id: user_id} = user_fixture(%{status: :trial, trial_expires_at: yesterday})

      {:error, :inactive_user} =
        Aliases.create_email_alias(%{user_id: user_id, address: "foo@email.com"})
    end

    test "does not let a trial user create > 10 aliases" do
      tomorrow = NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :day)
      %{id: user_id} = user_fixture(%{status: :trial, trial_expires_at: tomorrow})

      Enum.each(1..10, fn idx ->
        {:ok, _email_alias} =
          Aliases.create_email_alias(%{user_id: user_id, address: "#{idx}@email.com"})
      end)

      {:error, :trial_limit_reached} =
        Aliases.create_email_alias(%{user_id: user_id, address: "foo@email.com"})
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

    test "actually deletes an alias on a custom domain" do
      %{id: user_id} = user_fixture()
      %{domain: domain} = custom_domain_fixture(%{user_id: user_id})
      email_alias = alias_fixture(%{user_id: user_id, address: "alias@#{domain}"})
      Aliases.delete_email_alias(email_alias.id)

      assert is_nil(Repo.get_by(EmailAlias, id: email_alias.id))
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
      assert metric.blocked == 0
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

  describe "increment_blocked!/1" do
    test "creates a new row for the date" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})

      Aliases.increment_blocked!(email_alias)

      metric = Repo.get_by!(EmailMetric, alias_id: email_alias.id)
      today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()
      assert metric.date == today
      assert metric.forwarded == 0
      assert metric.blocked == 1
    end

    test "increments an existing row" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})
      today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()
      Repo.insert!(%EmailMetric{alias_id: email_alias.id, date: today, blocked: 1})

      Aliases.increment_blocked!(email_alias)

      metric = Repo.get_by!(EmailMetric, alias_id: email_alias.id)
      assert metric.blocked == 2
    end

    test "increments blocked field on the alias" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})

      Aliases.increment_blocked!(email_alias)

      email_alias = Repo.reload(email_alias)
      assert email_alias.blocked == 1
    end
  end

  describe "increment_replied!/1" do
    test "creates a new row for the date" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})

      Aliases.increment_replied!(email_alias)

      metric = Repo.get_by!(EmailMetric, alias_id: email_alias.id)
      today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()
      assert metric.date == today
      assert metric.forwarded == 0
      assert metric.blocked == 0
      assert metric.replied == 1
    end

    test "increments an existing row" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})
      today = NaiveDateTime.utc_now() |> NaiveDateTime.to_date()
      Repo.insert!(%EmailMetric{alias_id: email_alias.id, date: today, replied: 1})

      Aliases.increment_replied!(email_alias)

      metric = Repo.get_by!(EmailMetric, alias_id: email_alias.id)
      assert metric.replied == 2
    end

    test "increments replied field on the alias" do
      %{id: id} = user_fixture()
      email_alias = alias_fixture(%{user_id: id})

      Aliases.increment_replied!(email_alias)

      email_alias = Repo.reload(email_alias)
      assert email_alias.replied == 1
    end
  end
end
