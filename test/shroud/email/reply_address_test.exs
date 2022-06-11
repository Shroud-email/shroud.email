defmodule Shroud.Email.ReplyAddressTest do
  use ExUnit.Case, async: true

  alias Shroud.Email.ReplyAddress

  describe "to_reply_address/1" do
    test "translates email address to reply address" do
      assert ReplyAddress.to_reply_address("test@test.com", "deadbeef@shroud.test") ==
               "test_at_test.com_deadbeef@shroud.test"
    end

    test "handles underscores" do
      assert ReplyAddress.to_reply_address("test_one@test.com", "deadbeef@shroud.test") ==
               "test_one_at_test.com_deadbeef@shroud.test"
    end

    test "handles _at_" do
      assert ReplyAddress.to_reply_address("email_at_test@test.com", "deadbeef@shroud.test") ==
               "email_at_test_at_test.com_deadbeef@shroud.test"
    end
  end

  describe "from_reply_address/1" do
    test "translates reply address to email address" do
      assert ReplyAddress.from_reply_address("test_at_test.com_deadbeef@shroud.test") ==
               {"test@test.com", "deadbeef@shroud.test"}
    end

    test "handles underscores" do
      assert ReplyAddress.from_reply_address("test_one_at_test.com_deadbeef@shroud.test") ==
               {"test_one@test.com", "deadbeef@shroud.test"}
    end

    test "handles _at_" do
      assert ReplyAddress.from_reply_address("email_at_test_at_test.com_deadbeef@shroud.test") ==
               {"email_at_test@test.com", "deadbeef@shroud.test"}
    end
  end

  describe "is_reply_address?/1" do
    test "returns true for reply addresses" do
      assert ReplyAddress.is_reply_address?("name_at_example.com_alias@shroud.test")
    end

    test "returns false for other domain" do
      refute ReplyAddress.is_reply_address?("name_at_example.com_alias@other.com")
    end

    test "returns false for email aliases" do
      refute ReplyAddress.is_reply_address?("deadbeef@shroud.test")
    end

    test "returns false for any other email" do
      refute ReplyAddress.is_reply_address?("example@example.com")
    end
  end

  describe "reversible" do
    test "handles valid email addresses" do
      addresses = [
        "email@example.com",
        "firstname.lastname@example.com",
        "email@subdomain.example.com",
        "firstname+lastname@example.com",
        "email@123.123.123.123",
        "email@[123.123.123.123]",
        "\"email\"@example.com",
        "1234567890@example.com",
        "email@example-one.com",
        "_______@example.com",
        "email@example.name",
        "email@example.museum",
        "email@example.co.jp",
        "firstname-lastname@example.com",
        "much.\"more\\ unusual”@example.com",
        "very.unusual.\"@\".unusual.com@example.com",
        "very.\"(),:;<>[]\".VERY.\"very@\\\\ \"very\".unusual@strange.example.com"
      ]

      Enum.each(addresses, fn address ->
        email_alias = "deadbeef@shroud.test"

        assert {address, email_alias} ==
                 address
                 |> ReplyAddress.to_reply_address(email_alias)
                 |> ReplyAddress.from_reply_address()
      end)
    end
  end
end
