defmodule Shroud.Mcp.ToolsCreationTest do
  use Shroud.DataCase, async: true

  alias Shroud.{Aliases, Repo}
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Mcp.Tools
  import Shroud.DomainFixtures
  import Shroud.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  test "custom alias creation uses the existing changeset's address validation", context do
    domain = custom_domain_fixture(%{user_id: context.user.id})

    for local <- ["shop.orders", "shop+news", "shop!", ".shop", "shop.", "a..b"] do
      assert {:ok, %{address: address}} = create(context.user, domain.domain, local)
      assert address == local <> "@" <> domain.domain
    end

    for local <- ["shop_orders", "shop orders", "shop@other.com"] do
      assert {:error, _, %{error_code: "INVALID_ARGUMENT"}} =
               create(context.user, domain.domain, local)
    end

    assert Repo.aggregate(EmailAlias, :count) == 6
  end

  test "mixed-case owned domain retains association, deletion and address reuse", context do
    domain = custom_domain_fixture(%{user_id: context.user.id, domain: "Example.com"})

    for requested <- [domain.domain, "example.com", "EXAMPLE.COM"] do
      assert {:ok, %{address: "shop@example.com"}} =
               create(context.user, requested, "Shop")

      email_alias = Repo.get_by!(EmailAlias, address: "shop@example.com")
      assert email_alias.domain_id == domain.id
      assert email_alias.user_id == context.user.id
      assert {:ok, _} = Aliases.update_email_alias(email_alias, %{enabled: false})

      assert {:error, message, %{error_code: "ALIAS_ALREADY_EXISTS", address: "shop@example.com"}} =
               create(context.user, requested, "SHOP")

      assert message =~ "including as a disabled alias"
      assert {:ok, _} = Aliases.delete_email_alias(email_alias.id)
      refute Repo.get(EmailAlias, email_alias.id)
    end
  end

  test "case-insensitive matching never authorizes foreign or unverified domains", context do
    foreign = custom_domain_fixture(%{user_id: user_fixture().id, domain: "Foreign.com"})

    unverified =
      custom_domain_fixture(%{
        user_id: context.user.id,
        domain: "Unverified.com",
        ownership_verified_at: nil
      })

    for domain <- [foreign, unverified],
        requested <- [domain.domain, String.downcase(domain.domain), String.upcase(domain.domain)] do
      expected = if domain.id == foreign.id, do: "DOMAIN_NOT_FOUND", else: "DOMAIN_NOT_VERIFIED"

      assert {:error, _, %{error_code: ^expected}} =
               create(context.user, requested, "shop")

      assert {:error, _, %{error_code: ^expected}} =
               Tools.call(%{user: context.user}, "create_alias", %{
                 "title" => "Shopping",
                 "domain" => requested
               })
    end

    assert Repo.aggregate(EmailAlias, :count) == 0
  end

  test "random creation retains metadata and takes identity from the user", %{user: user} do
    other = user_fixture()

    assert {:error, "Invalid tool arguments", %{error_code: "INVALID_ARGUMENT"}} =
             Tools.call(%{user: user}, "create_alias", %{
               "title" => "Shopping",
               "user_id" => other.id
             })

    assert {:ok, %{address: address}} =
             Tools.call(%{user: user}, "create_alias", %{
               "title" => "Shopping",
               "notes" => "Receipts"
             })

    email_alias = Repo.get_by!(EmailAlias, address: address)
    assert email_alias.user_id == user.id
    assert email_alias.title == "Shopping"
    assert email_alias.notes == "Receipts"
    assert email_alias.enabled
  end

  test "custom domains generate random aliases with metadata and ownership", %{user: user} do
    domain = custom_domain_fixture(%{user_id: user.id, domain: "Example.com"})

    addresses =
      for _ <- 1..2 do
        assert {:ok, %{address: address, title: "Shopping", notes: "Receipts", enabled: true}} =
                 Tools.call(%{user: user}, "create_alias", %{
                   "title" => "Shopping",
                   "notes" => "Receipts",
                   "domain" => "EXAMPLE.COM"
                 })

        assert address =~ ~r/^[a-z0-9]{16}@example\.com$/
        email_alias = Repo.get_by!(EmailAlias, address: address)
        assert email_alias.user_id == user.id
        assert email_alias.domain_id == domain.id
        address
      end

    assert length(Enum.uniq(addresses)) == 2
  end

  defp create(user, domain, local) do
    Tools.call(%{user: user}, "create_alias", %{
      "title" => "Shopping",
      "domain" => domain,
      "local_part" => local
    })
  end
end
