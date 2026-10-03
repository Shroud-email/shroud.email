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

    for local <- ["shop_orders", "shop orders"] do
      assert {:error, _} = create(context.user, domain.domain, local)
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
      assert {:error, _} = create(context.user, requested, "shop")
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
      assert {:error, "Supply both a valid local part and an existing verified custom domain"} =
               create(context.user, requested, "shop")
    end

    assert Repo.aggregate(EmailAlias, :count) == 0
  end

  test "random creation retains metadata and takes identity from the user", %{user: user} do
    other = user_fixture()

    assert {:error, "Invalid tool arguments"} =
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

  defp create(user, domain, local) do
    Tools.call(%{user: user}, "create_alias", %{
      "title" => "Shopping",
      "domain" => domain,
      "local_part" => local
    })
  end
end
