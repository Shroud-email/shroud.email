defmodule Shroud.Email.ParsingFlagsTest do
  use Shroud.DataCase, async: true

  alias Shroud.Email.ParsingFlags

  import Shroud.AccountsFixtures

  describe "mailex_parsing_enabled?/1" do
    test "returns false for nil user" do
      assert ParsingFlags.mailex_parsing_enabled?(nil) == false
    end

    test "returns false when flag is disabled for a user" do
      user = user_fixture()
      FunWithFlags.disable(:mailex_parsing, for_actor: user)

      assert ParsingFlags.mailex_parsing_enabled?(user) == false
    end

    test "returns true when flag is enabled for user" do
      user = user_fixture()
      FunWithFlags.enable(:mailex_parsing, for_actor: user)

      assert ParsingFlags.mailex_parsing_enabled?(user) == true
    end
  end
end
