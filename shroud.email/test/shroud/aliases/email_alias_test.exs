defmodule Shroud.Aliases.EmailAliasTest do
  use Shroud.DataCase, async: false
  alias Shroud.Aliases.EmailAlias
  import Shroud.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "changeset/2" do
    test "prevents spaces in local part", %{user: user} do
      changeset =
        EmailAlias.changeset(%EmailAlias{}, %{address: "foo bar@test.com", user_id: user.id})

      refute changeset.valid?
    end

    test "prevents underscores in local part", %{user: user} do
      changeset =
        EmailAlias.changeset(%EmailAlias{}, %{address: "foo_bar@test.com", user_id: user.id})

      refute changeset.valid?
    end
  end
end
