defmodule Shroud.PermissionsTest do
  use Shroud.DataCase

  alias Shroud.Aliases.EmailAlias

  import Shroud.{AccountsFixtures, AliasesFixtures}
  import Canada, only: [can?: 2]

  setup do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    yesterday = NaiveDateTime.add(now, -1 * 60 * 60 * 24)
    tomorrow = NaiveDateTime.add(now, 60 * 60 * 24)

    %{yesterday: yesterday, tomorrow: tomorrow}
  end

  describe("User permissions") do
    test "active trial users can read/update/destroy aliases", %{tomorrow: tomorrow} do
      user = user_fixture(%{status: :trial, trial_expires_at: tomorrow})
      email_alias = alias_fixture(%{user_id: user.id})

      assert user |> can?(read(email_alias))
      assert user |> can?(update(email_alias))
      assert user |> can?(destroy(email_alias))
    end

    test "active trial users can create aliases", %{tomorrow: tomorrow} do
      user = user_fixture(%{status: :trial, trial_expires_at: tomorrow})

      assert user |> can?(create(EmailAlias))
    end

    test "expired trial users can read/update/destroy aliases", %{yesterday: yesterday} do
      user = user_fixture(%{status: :trial, trial_expires_at: yesterday})
      email_alias = alias_fixture(%{user_id: user.id})

      assert user |> can?(read(email_alias))
      assert user |> can?(update(email_alias))
      assert user |> can?(destroy(email_alias))
    end

    test "expired trial users cannot create aliases", %{yesterday: yesterday} do
      user = user_fixture(%{status: :trial, trial_expires_at: yesterday})

      refute user |> can?(create(EmailAlias))
    end

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
  end
end
