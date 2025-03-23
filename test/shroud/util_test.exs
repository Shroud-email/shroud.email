defmodule Shroud.UtilTest do
  use ExUnit.Case, async: true
  doctest Shroud.Util

  alias Shroud.Util

  setup do
    map = %{string: "value", number: 123, array: ["one", "two"]}
    %{map: map}
  end

  describe "uri_decode_map/1" do
    test "decodes a valid string", %{map: map} do
      encoded = Util.uri_encode_map!(map)
      {:ok, decoded} = Util.uri_decode_map(encoded)

      expected = %{"array" => ["one", "two"], "number" => 123, "string" => "value"}
      assert decoded == expected
    end

    test "returns error for an invalid string" do
      assert :error == Util.uri_decode_map("deadbeef")
    end
  end

  describe "email_domain/0" do
    test "returns the email domain" do
      assert Util.email_domain() == "email.shroud.test"
    end
  end
end
