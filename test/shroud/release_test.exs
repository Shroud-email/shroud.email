defmodule Shroud.ReleaseTest do
  # System config is global so these tests must not be run in parallel
  use Shroud.DataCase, async: false
  alias Shroud.{Accounts, Aliases, Release, Repo}

  import Shroud.AccountsFixtures
  import Shroud.AliasesFixtures
  import Swoosh.TestAssertions

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

  describe "make_emails_case_insensitive/0" do
    test "makes all emails case insensitive" do
      user = user_fixture()

      alias_1 =
        alias_fixture(%{
          user_id: user.id,
          address: "alias@example.com",
          forwarded: 5,
          title: "One",
          notes: "One"
        })

      alias_2 =
        alias_fixture(%{
          user_id: user.id,
          address: "ALIAS@example.com",
          forwarded: 5,
          title: "Two",
          notes: "Two"
        })

      metric_fixture(%{alias_id: alias_1.id, date: Date.utc_today(), forwarded: 1})
      metric_fixture(%{alias_id: alias_2.id, date: Date.utc_today(), forwarded: 1})

      Release.make_emails_case_insensitive()

      # aliases are merged
      alias_1 = Repo.reload(alias_1)
      assert alias_1.address == "alias@example.com"
      assert is_nil(Repo.reload(alias_2))

      # metrics are merged
      assert alias_1.forwarded == 10
      alias_1_with_metrics = Aliases.get_email_alias_by_address!(alias_1.address)
      assert alias_1_with_metrics.forwarded_in_last_30_days == 2

      # titles and notes are merged
      assert alias_1.title == "One\nTwo"
      assert alias_1.notes == "One\nTwo"
    end

    test "does nothing to non-duplicate emails" do
      user = user_fixture()

      email_alias =
        alias_fixture(%{
          user_id: user.id,
          address: "alias@example.com",
          forwarded: 5,
          title: "One",
          notes: "One"
        })

      metric_fixture(%{alias_id: email_alias.id, date: Date.utc_today(), forwarded: 1})

      metric_fixture(%{
        alias_id: email_alias.id,
        date: Date.utc_today() |> Date.add(-1),
        forwarded: 1
      })

      Release.make_emails_case_insensitive()

      # alias still exists
      email_alias = Repo.reload(email_alias)
      assert email_alias.address == "alias@example.com"
      assert email_alias.forwarded == 5
      assert email_alias.title == "One"
      assert email_alias.notes == "One"

      # metrics still there
      alias_with_metrics = Aliases.get_email_alias_by_address!(email_alias.address)
      assert alias_with_metrics.forwarded_in_last_30_days == 2
    end

    test "makes all emails lowercase" do
      user = user_fixture()

      email_alias =
        alias_fixture(%{
          user_id: user.id,
          address: "ALIAS@example.com"
        })

      Release.make_emails_case_insensitive()

      email_alias = Repo.reload(email_alias)
      assert email_alias.address == "alias@example.com"
    end
  end
end
