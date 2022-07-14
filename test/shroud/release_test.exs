defmodule Shroud.ReleaseTest do
  # System config is global so these tests must not be run in parallel
  use Shroud.DataCase, async: false
  alias Shroud.{Accounts, Release, Repo}

  import Shroud.AccountsFixtures
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
end
