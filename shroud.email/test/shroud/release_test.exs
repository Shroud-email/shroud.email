defmodule Shroud.ReleaseTest do
  # System config is global so these tests must not be run in parallel
  use Shroud.DataCase, async: false
  alias Shroud.{Accounts, Release, Repo}
  alias Shroud.Aliases.{EmailAlias, EmailMetric}

  import Shroud.AccountsFixtures
  import Shroud.AliasesFixtures
  import Swoosh.TestAssertions

  describe "make_emails_case_insensitive/0" do
    test "retains metrics from duplicate aliases on every date" do
      allow_legacy_case_sensitive_aliases()
      user = user_fixture()
      first = duplicate_alias_fixture(user.id, "alias@example.com")
      second = duplicate_alias_fixture(user.id, "ALIAS@example.com")

      metric_fixture(%{alias_id: first.id, date: ~D[2023-01-01], forwarded: 1})
      metric_fixture(%{alias_id: second.id, date: ~D[2023-01-01], forwarded: 2})
      metric_fixture(%{alias_id: second.id, date: ~D[2023-01-02], blocked: 3})

      Release.make_emails_case_insensitive()

      assert [%EmailAlias{id: first_id, address: "alias@example.com"}] = Repo.all(EmailAlias)

      assert [
               %EmailMetric{date: ~D[2023-01-01], forwarded: 3, blocked: 0},
               %EmailMetric{date: ~D[2023-01-02], forwarded: 0, blocked: 3}
             ] = Repo.all(from m in EmailMetric, where: m.alias_id == ^first_id, order_by: m.date)
    end

    test "merges asymmetric metrics independently across multiple dates" do
      allow_legacy_case_sensitive_aliases()
      user = user_fixture()
      first = duplicate_alias_fixture(user.id, "other@example.com")
      second = duplicate_alias_fixture(user.id, "OTHER@example.com")
      third = duplicate_alias_fixture(user.id, "Other@example.com")

      metric_fixture(%{alias_id: first.id, date: ~D[2023-02-01], replied: 1})
      metric_fixture(%{alias_id: second.id, date: ~D[2023-02-02], forwarded: 2})
      metric_fixture(%{alias_id: third.id, date: ~D[2023-02-02], forwarded: 3})
      metric_fixture(%{alias_id: third.id, date: ~D[2023-02-03], blocked: 4})

      Release.make_emails_case_insensitive()

      assert [
               %EmailMetric{date: ~D[2023-02-01], replied: 1},
               %EmailMetric{date: ~D[2023-02-02], forwarded: 5},
               %EmailMetric{date: ~D[2023-02-03], blocked: 4}
             ] = Repo.all(from m in EmailMetric, order_by: m.date)
    end
  end

  describe "create_admin_user/0" do
    test "creates an admin user if it doesn't exist" do
      Application.put_env(:shroud, :admin_user_email, "admin@test.com")
      Release.create_admin_user()
      user = Accounts.get_user_by_email("admin@test.com")

      assert user
      assert user.status == :lifetime
      assert user.is_admin
      refute is_nil(user.confirmed_at)
      assert_email_sent(to: "admin@test.com", subject: "Reset password")
    end

    test "doesn't create an admin user if it already exists" do
      user = user_fixture(%{email: "admin@test.com"})
      Application.put_env(:shroud, :admin_user_email, "admin@test.com")
      Release.create_admin_user()

      # just ensure that the function did not fail
      assert Repo.reload(user)
    end

    test "does nothing if environment variables are not set" do
      Application.delete_env(:shroud, :admin_user_email)
      Release.create_admin_user()

      refute Accounts.get_user_by_email("admin@test.com")
      assert_no_email_sent()
    end

    test "raises an error if the admin email isn't valid" do
      Application.put_env(:shroud, :admin_user_email, "not-an-email")

      assert_raise Ecto.InvalidChangesetError, fn ->
        Release.create_admin_user()
      end

      assert_no_email_sent()
    end
  end

  defp duplicate_alias_fixture(user_id, address) do
    Repo.insert!(%EmailAlias{user_id: user_id, address: address})
  end

  defp allow_legacy_case_sensitive_aliases do
    Repo.query!("DROP INDEX email_aliases_address_index")
  end
end
