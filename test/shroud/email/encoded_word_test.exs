defmodule Shroud.Email.EncodedWordTest do
  use Shroud.DataCase, async: true

  alias Shroud.Email.EncodedWord

  describe "decode/1" do
    test "decodes a single word" do
      assert "foo" == EncodedWord.decode("=?utf-8?Q?foo?=")
    end

    test "decodes emojis" do
      result = EncodedWord.decode("=?utf-8?Q?=C2=A3?=200.00 =?UTF-8?q?=F0=9F=92=B5?=")
      assert result == "£200.00 💵"
    end

    test "decodes multiple words" do
      assert "foo bar" == EncodedWord.decode("=?utf-8?Q?foo?= =?utf-8?Q?bar?=")
    end
  end
end
