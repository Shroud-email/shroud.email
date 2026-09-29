defmodule Shroud.PermissionsTest do
  use Shroud.DataCase

  alias Shroud.Aliases.EmailAlias

  import Shroud.{AccountsFixtures, AliasesFixtures}
  import Canada, only: [can?: 2]

  describe("User permissions") do
    test "active users can read/update/destroy aliases" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})

      assert user |> can?(read(email_alias))
      assert user |> can?(update(email_alias))
      assert user |> can?(destroy(email_alias))
    end

    test "active users can create aliases" do
      user = user_fixture(%{status: :active})

      assert user |> can?(create(EmailAlias))
    end

    test "free users can read/update/destroy their own aliases" do
      user = user_fixture(%{status: :free})
      email_alias = alias_fixture(%{user_id: user.id})

      assert user |> can?(read(email_alias))
      assert user |> can?(update(email_alias))
      assert user |> can?(destroy(email_alias))
    end

    test "free users can create aliases" do
      user = user_fixture(%{status: :free})

      assert user |> can?(create(EmailAlias))
    end

    test "lifetime users can read/update/destroy their own aliases" do
      user = user_fixture(%{status: :lifetime})
      email_alias = alias_fixture(%{user_id: user.id})

      assert user |> can?(read(email_alias))
      assert user |> can?(update(email_alias))
      assert user |> can?(destroy(email_alias))
    end

    test "lifetime users can create aliases" do
      user = user_fixture(%{status: :lifetime})

      assert user |> can?(create(EmailAlias))
    end

    test "inactive users can read/update/destroy their own aliases" do
      # Create the alias while active, then deactivate the user.
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})

      {:ok, _} =
        user
        |> Shroud.Accounts.User.status_changeset(%{status: :inactive})
        |> Shroud.Repo.update()

      user = Shroud.Repo.reload!(user)

      assert user |> can?(read(email_alias))
      assert user |> can?(update(email_alias))
      assert user |> can?(destroy(email_alias))
    end

    test "inactive users cannot create aliases" do
      user = user_fixture(%{status: :inactive})

      refute user |> can?(create(EmailAlias))
    end
  end
end
