defmodule Shroud.Email.ReplyAddressTest do
  use Shroud.DataCase, async: false
  doctest Shroud.Email.ReplyAddress

  import Shroud.DomainFixtures
  import Shroud.AccountsFixtures
  import Shroud.AliasesFixtures
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

  describe "subdomain reply addresses" do
    setup do
      previous = Application.get_env(:shroud, :reply_address_subdomains_enabled)
      Application.put_env(:shroud, :reply_address_subdomains_enabled, true)
      on_exit(fn -> Application.put_env(:shroud, :reply_address_subdomains_enabled, previous) end)
      user = user_fixture()
      %{email_alias: alias_fixture(%{user_id: user.id})}
    end

    test "preserves local case, canonicalizes domain case and decodes after rollback", %{
      email_alias: a
    } do
      route = ReplyAddress.to_reply_address("Mixed+_at_@EXAMPLE.COM", a.address)
      assert route == "Mixed+_at_@mv4gc3lqnrss4y3pnu.#{a.id}.r1.reply.email.shroud.test"
      Application.put_env(:shroud, :reply_address_subdomains_enabled, false)
      {local, domain} = Shroud.Util.extract_email_parts(route)

      assert ReplyAddress.from_reply_address(local <> "@" <> String.upcase(domain)) ==
               {"Mixed+_at_@example.com", a.address}

      assert ReplyAddress.from_reply_address("sender_at_example.com_alias@email.shroud.test") ==
               {"sender@example.com", "alias@email.shroud.test"}
    end

    test "uses existing alias identity for custom domains", %{email_alias: a} do
      custom_domain = custom_domain_fixture(%{user_id: a.user_id, domain: "custom.example"})

      custom_alias =
        alias_fixture(%{
          user_id: a.user_id,
          address: "mine@custom.example",
          domain_id: custom_domain.id
        })

      route = ReplyAddress.to_reply_address("sender@example.com", custom_alias.address)
      assert String.ends_with?(route, ".#{custom_alias.id}.r1.reply.email.shroud.test")

      assert ReplyAddress.from_reply_address(route) ==
               {"sender@example.com", custom_alias.address}

      Shroud.Aliases.delete_email_alias(custom_alias.id)
      assert ReplyAddress.from_reply_address(route) == :error
    end

    test "enforces octet limits and chunks DNS payloads at 63", %{email_alias: a} do
      local = String.duplicate("a", 64)
      domain = String.duplicate("b", 39) <> ".example"
      route = ReplyAddress.to_reply_address(local <> "@" <> domain, a.address)
      assert is_binary(route)
      {^local, route_domain} = Shroud.Util.extract_email_parts(route)
      [payload | labels] = String.split(route_domain, ".")
      assert byte_size(payload) == 63
      assert Enum.all?(labels, &(byte_size(&1) <= 63))
      assert ReplyAddress.from_reply_address(route) == {local <> "@" <> domain, a.address}
      assert ReplyAddress.to_reply_address("a" <> local <> "@example.com", a.address) == :error

      assert ReplyAddress.to_reply_address("a@" <> String.duplicate("b", 64) <> ".com", a.address) ==
               :error

      # Independently derive the longest local allowed by the whole-address limit.
      long_domain = String.duplicate("b", 63) <> "." <> String.duplicate("c", 50) <> ".com"
      encoded_length = div(byte_size(long_domain) * 8 + 4, 5)
      chunks = div(encoded_length + 62, 63)

      route_domain_length =
        encoded_length + chunks + byte_size(Integer.to_string(a.id)) +
          byte_size("reply.email.shroud.test") + 4

      max_local = 254 - route_domain_length - 1
      assert max_local in 1..63

      at_limit =
        ReplyAddress.to_reply_address(
          String.duplicate("d", max_local) <> "@" <> long_domain,
          a.address
        )

      assert byte_size(at_limit) == 254

      assert ReplyAddress.from_reply_address(at_limit) ==
               {String.duplicate("d", max_local) <> "@" <> long_domain, a.address}

      assert ReplyAddress.to_reply_address(
               String.duplicate("d", max_local + 1) <> "@" <> long_domain,
               a.address
             ) == :error

      assert ReplyAddress.from_reply_address("d" <> at_limit) == :error
    end

    test "rejects malformed, noncanonical, unknown and deleted routes", %{email_alias: a} do
      route = ReplyAddress.to_reply_address("sender@example.com", a.address)

      for invalid <- [
            String.replace(route, ".r1.", ".r2."),
            String.replace(route, ".#{a.id}.", ".0#{a.id}."),
            String.replace(route, ".#{a.id}.", ".9223372036854775808."),
            String.replace(route, ".#{a.id}.", ".0."),
            String.replace(route, "mv4gc3lqnrss4y3pnu", "mv4.gc3lqnrss4y3pnu"),
            String.replace(route, "mv4gc3lqnrss4y3pnu", "mv4gc3lqnrss4y3pnv"),
            "sender@reply.email.shroud.test",
            "sender@invalid.#{a.id}.r1.reply.email.shroud.test"
          ] do
        assert ReplyAddress.reply_address?(invalid)
        assert ReplyAddress.from_reply_address(invalid) == :error
      end

      refute ReplyAddress.reply_address?(route <> ".evil.example")
      refute ReplyAddress.reply_address?("x_at_example.com_alias@email.shroud.test.evil.example")
      Shroud.Aliases.delete_email_alias(a.id)
      assert ReplyAddress.from_reply_address(route) == :error
    end

    test "does not repair unsupported mailboxes into a different identity", %{email_alias: a} do
      for address <- [
            "\"a b\"@example.com",
            "\"a@b\"@example.com",
            "a b@example.com",
            "a@[127.0.0.1]",
            "ü@example.com",
            "a@例.example",
            "a..b@example.com",
            "a@my_domain.example"
          ] do
        assert ReplyAddress.to_reply_address(address, a.address) == :error
      end
    end
  end

  describe "to_reply_address/2" do
    test "translates email address to reply address" do
      assert ReplyAddress.to_reply_address("test@test.com", "deadbeef@email.shroud.test") ==
               "test_at_test.com_deadbeef@email.shroud.test"
    end

    test "handles custom domains" do
      assert ReplyAddress.to_reply_address("sender@example.com", "alias@custom.com") ==
               "sender_at_example.com_alias@custom.com"
    end

    test "handles underscores" do
      assert ReplyAddress.to_reply_address("test_one@test.com", "deadbeef@email.shroud.test") ==
               "test_one_at_test.com_deadbeef@email.shroud.test"
    end

    test "handles _at_" do
      assert ReplyAddress.to_reply_address("email_at_test@test.com", "deadbeef@email.shroud.test") ==
               "email_at_test_at_test.com_deadbeef@email.shroud.test"
    end

    test "handles underscores in recipient domains" do
      assert ReplyAddress.to_reply_address("test@test_one.com", "deadbeef@email.shroud.test") ==
               "test_at_test_one.com_deadbeef@email.shroud.test"
    end

    test "handles underscores in alias domains" do
      assert ReplyAddress.to_reply_address("sender@example.com", "alias@my_custom.com") ==
               "sender_at_example.com_alias@my_custom.com"
    end
  end

  describe "from_reply_address/1" do
    test "translates reply address to email address" do
      assert ReplyAddress.from_reply_address("test_at_test.com_deadbeef@email.shroud.test") ==
               {"test@test.com", "deadbeef@email.shroud.test"}
    end

    test "translates reply address on custom domain to email address" do
      assert ReplyAddress.from_reply_address("test_at_test.com_deadbeef@custom.com") ==
               {"test@test.com", "deadbeef@custom.com"}
    end

    test "handles underscores" do
      assert ReplyAddress.from_reply_address("test_one_at_test.com_deadbeef@email.shroud.test") ==
               {"test_one@test.com", "deadbeef@email.shroud.test"}
    end

    test "handles _at_" do
      assert ReplyAddress.from_reply_address(
               "email_at_test_at_test.com_deadbeef@email.shroud.test"
             ) ==
               {"email_at_test@test.com", "deadbeef@email.shroud.test"}
    end

    test "handles underscores in recipient domains" do
      assert ReplyAddress.from_reply_address("test_at_test_one.com_deadbeef@email.shroud.test") ==
               {"test@test_one.com", "deadbeef@email.shroud.test"}
    end

    test "handles underscores in alias domains" do
      assert ReplyAddress.from_reply_address("sender_at_example.com_alias@my_custom.com") ==
               {"sender@example.com", "alias@my_custom.com"}
    end
  end

  describe "reply_address?/1" do
    test "returns true for legacy reply addresses" do
      assert ReplyAddress.reply_address?("name_at_example.com_alias@email.shroud.test")
    end

    test "returns true for reply addresses on a custom domain" do
      custom_domain_fixture(%{domain: "custom.com"})
      assert ReplyAddress.reply_address?("name_at_example.com_alias@custom.com")
    end

    test "returns false for other domain" do
      refute ReplyAddress.reply_address?("name_at_example.com_alias@other.com")
    end

    test "returns false for email aliases" do
      refute ReplyAddress.reply_address?("deadbeef@email.shroud.test")
    end

    test "returns false for any other email" do
      refute ReplyAddress.reply_address?("example@example.com")
    end
  end

  describe "reversible" do
    test "handles valid email addresses" do
      Enum.each(@email_addresses, fn address ->
        email_alias = "deadbeef@email.shroud.test"

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
