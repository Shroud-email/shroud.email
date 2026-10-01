defmodule Shroud.McpToolsValidationTest do
  use Shroud.DataCase, async: true

  alias Shroud.{Aliases, Repo}
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Mcp.Tools
  import Shroud.DomainFixtures
  import Shroud.McpFixtures

  setup do
    user = confirmed_user()
    %{user: user, connection: %{user: user, user_id: user.id}}
  end

  test "rejects dot placement accepted by the character allowlist", context do
    domain = custom_domain_fixture(%{user_id: context.user.id})

    for local <- [".shop", "shop.", "a..b"] do
      assert Regex.match?(~r/^[A-Za-z0-9.!#$%&'*+\/=?^`{|}~-]+$/, local)
      refute match?({:ok, [{:undefined, _}]}, parse(local, domain.domain))
      assert {:error, _} = create(context.connection, domain.domain, local)
    end

    assert Repo.aggregate(EmailAlias, :count) == 0
  end

  test "accepts valid dot atoms but retains the no-underscore policy", context do
    domain = custom_domain_fixture(%{user_id: context.user.id})

    for local <- ["shop.orders", "shop+news", "shop!"] do
      assert {:ok, [{:undefined, _}]} = parse(local, domain.domain)
      assert {:ok, %{address: address}} = create(context.connection, domain.domain, local)
      assert address == local <> "@" <> domain.domain
    end

    assert {:ok, [{:undefined, _}]} = parse("shop_orders", domain.domain)
    assert {:error, _} = create(context.connection, domain.domain, "shop_orders")
    assert Repo.aggregate(EmailAlias, :count) == 3
  end

  test "mixed-case owned domain retains association, deletion and address reuse", context do
    domain = custom_domain_fixture(%{user_id: context.user.id, domain: "Example.com"})

    for requested <- [domain.domain, "example.com", "EXAMPLE.COM"] do
      assert {:ok, %{address: "shop@example.com"}} =
               create(context.connection, requested, "Shop")

      email_alias = Repo.get_by!(EmailAlias, address: "shop@example.com")
      assert email_alias.domain_id == domain.id
      assert email_alias.user_id == context.user.id
      assert {:error, _} = create(context.connection, requested, "shop")
      assert {:ok, _} = Aliases.delete_email_alias(email_alias.id)
      refute Repo.get(EmailAlias, email_alias.id)
    end
  end

  test "case-insensitive matching never authorizes foreign or unverified domains", context do
    foreign = custom_domain_fixture(%{user_id: confirmed_user().id, domain: "Foreign.com"})

    unverified =
      custom_domain_fixture(%{
        user_id: context.user.id,
        domain: "Unverified.com",
        ownership_verified_at: nil
      })

    for domain <- [foreign, unverified],
        requested <- [domain.domain, String.downcase(domain.domain), String.upcase(domain.domain)] do
      assert {:error, _} = create(context.connection, requested, "shop")
    end

    assert Repo.aggregate(EmailAlias, :count) == 0
  end

  defp create(connection, domain, local) do
    Tools.call(connection, "create_alias", %{
      "title" => "Shopping",
      "domain" => domain,
      "local_part" => local
    })
  end

  defp parse(local, domain), do: :smtp_util.parse_rfc5322_addresses(local <> "@" <> domain)
end
