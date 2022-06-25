defmodule Shroud.ReleaseTest do
  # System config is global so these tests must not be run in parallel
  use Shroud.DataCase, async: false
  alias Shroud.{Accounts, Release}

  import Shroud.{AccountsFixtures, AliasesFixtures, Repo}
  import Swoosh.TestAssertions

  describe "create_admin_user/0" do
    test "creates an admin user if it doesn't exist" do
      Application.put_env(:shroud, :admin_user_email, "test@test.com")
      Release.create_admin_user()
      user = Accounts.get_user_by_email("test@test.com")

      assert user
      assert user.status == :lifetime
      assert_email_sent(to: "test@test.com", subject: "Confirmation instructions")
      assert_email_sent(to: "test@test.com", subject: "Reset password")
    end

    test "doesn't create an admin user if it does exist" do
      user = user_fixture(%{email: "test@test.com"})
      Application.put_env(:shroud, :admin_user_email, "test@test.com")
      Release.create_admin_user()

      # just ensure that the function did not fail
      assert Repo.reload(user)
    end

    test "does nothing if environment variables are not set" do
      Application.delete_env(:shroud, :admin_user_email)
      Release.create_admin_user()

      refute Accounts.get_user_by_email("test@test.com")
      assert_no_email_sent()
    end
  end
end
