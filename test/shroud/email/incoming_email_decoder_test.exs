defmodule Shroud.Email.IncomingEmailDecoderTest do
  use Shroud.DataCase, async: true

  alias Shroud.Email.IncomingEmailDecoder

  import Shroud.AccountsFixtures

  @simple_email File.read!("test/support/data/real/simple.eml")

  describe "decode/2" do
    test "returns {:mimemail, tuple} when flag is disabled for user" do
      user = user_fixture()
      FunWithFlags.disable(:mailex_parsing, for_actor: user)

      result = IncomingEmailDecoder.decode(@simple_email, user)

      assert {:mimemail, mimetuple} = result
      assert is_tuple(mimetuple)
      assert elem(mimetuple, 0) == "multipart"
    end

    test "returns {:mimemail, tuple} when user is nil" do
      result = IncomingEmailDecoder.decode(@simple_email, nil)

      assert {:mimemail, mimetuple} = result
      assert is_tuple(mimetuple)
    end

    test "returns {:mailex, message} when flag is enabled for user" do
      user = user_fixture()
      FunWithFlags.enable(:mailex_parsing, for_actor: user)

      result = IncomingEmailDecoder.decode(@simple_email, user)

      assert {:mailex, %Mailex.Message{} = message} = result
      assert message.content_type.type == "multipart"
      assert message.content_type.subtype == "alternative"
    end
  end
end
