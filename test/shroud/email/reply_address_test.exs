defmodule Shroud.Email.ReplyAddressTest do
  use Shroud.DataCase, async: true
  doctest Shroud.Email.ReplyAddress

  import Shroud.DomainFixtures
  alias Shroud.Email.ReplyAddress

  @email_addresses [
    "email@example.com",
    "firstname.lastname@example.com",
    "email@subdomain.example.com",
    "firstname+lastname@example.com",
    "email@my_domain.co.uk",
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

  describe "to_reply_address/1" do
    test "translates email address to reply address" do
      assert ReplyAddress.to_reply_address("test@test.com", "deadbeef@shroud.test") ==
               "test_at_test.com_deadbeef@shroud.test"
    end

    test "handles custom domains" do
      assert ReplyAddress.to_reply_address("sender@example.com", "alias@custom.com") ==
               "sender_at_example.com_alias@custom.com"
    end

    test "handles underscores" do
      assert ReplyAddress.to_reply_address("test_one@test.com", "deadbeef@shroud.test") ==
               "test_one_at_test.com_deadbeef@shroud.test"
    end

    test "handles _at_" do
      assert ReplyAddress.to_reply_address("email_at_test@test.com", "deadbeef@shroud.test") ==
               "email_at_test_at_test.com_deadbeef@shroud.test"
    end

    test "handles underscores in recipient domains" do
      assert ReplyAddress.to_reply_address("test@test_one.com", "deadbeef@shroud.test") ==
               "test_at_test_one.com_deadbeef@shroud.test"
    end

    test "handles underscores in alias domains" do
      assert ReplyAddress.to_reply_address("sender@example.com", "alias@my_custom.com") ==
               "sender_at_example.com_alias@my_custom.com"
    end
  end

  describe "from_reply_address/1" do
    test "translates reply address to email address" do
      assert ReplyAddress.from_reply_address("test_at_test.com_deadbeef@shroud.test") ==
               {"test@test.com", "deadbeef@shroud.test"}
    end

    test "translates reply address on custom domain to email address" do
      assert ReplyAddress.from_reply_address("test_at_test.com_deadbeef@custom.com") ==
               {"test@test.com", "deadbeef@custom.com"}
    end

    test "handles underscores" do
      assert ReplyAddress.from_reply_address("test_one_at_test.com_deadbeef@shroud.test") ==
               {"test_one@test.com", "deadbeef@shroud.test"}
    end

    test "handles _at_" do
      assert ReplyAddress.from_reply_address("email_at_test_at_test.com_deadbeef@shroud.test") ==
               {"email_at_test@test.com", "deadbeef@shroud.test"}
    end

    test "handles underscores in recipient domains" do
      assert ReplyAddress.from_reply_address("test_at_test_one.com_deadbeef@shroud.test") ==
               {"test@test_one.com", "deadbeef@shroud.test"}
    end

    test "handles underscores in alias domains" do
      assert ReplyAddress.from_reply_address("sender_at_example.com_alias@my_custom.com") ==
               {"sender@example.com", "alias@my_custom.com"}
    end
  end

  describe "reply_address?/1" do
    test "returns true for legacy reply addresses" do
      assert ReplyAddress.reply_address?("name_at_example.com_alias@shroud.test")
    end

    test "returns true for reply addresses on a custom domain" do
      custom_domain_fixture(%{domain: "custom.com"})
      assert ReplyAddress.reply_address?("name_at_example.com_alias@custom.com")
    end

    test "returns false for other domain" do
      refute ReplyAddress.reply_address?("name_at_example.com_alias@other.com")
    end

    test "returns false for email aliases" do
      refute ReplyAddress.reply_address?("deadbeef@shroud.test")
    end

    test "returns false for any other email" do
      refute ReplyAddress.reply_address?("example@example.com")
    end
  end

  describe "reversible" do
    test "handles valid email addresses" do
      Enum.each(@email_addresses, fn address ->
        email_alias = "deadbeef@shroud.test"

        assert {address, email_alias} ==
                 address
                 |> ReplyAddress.to_reply_address(email_alias)
                 |> ReplyAddress.from_reply_address()
      end)
    end

    test "handles valid email addresses on custom domains" do
      Enum.each(@email_addresses, fn address ->
        email_alias = "deadbeef@custom.com"

        assert {address, email_alias} ==
                 address
                 |> ReplyAddress.to_reply_address(email_alias)
                 |> ReplyAddress.from_reply_address()
      end)
    end
  end
end
