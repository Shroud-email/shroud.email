defmodule Shroud.DomainTest do
  use Shroud.DataCase

  alias Shroud.Domain

  alias Shroud.Domain.CustomDomain

  import Shroud.DomainFixtures
  import Shroud.AccountsFixtures

  describe "list_custom_domains/1" do
    test "list_custom_domains/1 returns all custom_domains for the user" do
      user = user_fixture()
      custom_domain = custom_domain_fixture(%{user_id: user.id})
      assert Domain.list_custom_domains(user) == [custom_domain]
    end

    test "list_custom_domains/1 does not return other's domains" do
      user = user_fixture()
      _custom_domain = custom_domain_fixture(%{user_id: user.id})
      other_user = user_fixture()
      assert Domain.list_custom_domains(other_user) == []
    end
  end

  describe "get_custom_domain!/2" do
    test "get_custom_domain!/2 returns the custom_domain with given domain/user" do
      user = user_fixture()
      custom_domain = custom_domain_fixture(%{user_id: user.id, domain: "example.com"})
      assert Domain.get_custom_domain!(user, "example.com") == custom_domain
    end

    test "get_custom_domain!/2 does not return another's domain" do
      user = user_fixture()
      _custom_domain = custom_domain_fixture(%{user_id: user.id, domain: "example.com"})
      other_user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Domain.get_custom_domain!(other_user, "example.com")
      end
    end
  end

  describe "create_custom_domain/2" do
    test "create_custom_domain/2 with valid data creates a custom_domain" do
      user = user_fixture()
      valid_attrs = %{domain: "example.com"}

      assert {:ok, %CustomDomain{} = custom_domain} =
               Domain.create_custom_domain(user, valid_attrs)

      refute custom_domain.catchall_enabled
      assert custom_domain.dkim_verified_at == nil
      assert custom_domain.dmarc_verified_at == nil
      assert custom_domain.domain == "example.com"
      assert custom_domain.mx_verified_at == nil
      assert custom_domain.spf_verified_at == nil
      assert custom_domain.ownership_verified_at == nil
      refute is_nil(custom_domain.verification_code)
    end

    test "create_custom_domain/1 with invalid data returns error changeset" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Domain.create_custom_domain(user, %{domain: "not-domain"})
    end
  end

  describe "update_custom_domain/2" do
    test "update_custom_domain/2 with valid data updates the custom_domain" do
      custom_domain = custom_domain_fixture()
      update_attrs = %{catchall_enabled: false}

      assert {:ok, %CustomDomain{} = custom_domain} =
               Domain.update_custom_domain(custom_domain, update_attrs)

      assert custom_domain.catchall_enabled == false
    end
  end

  describe "delete_custom_domain/1" do
    test "delete_custom_domain/1 deletes the custom_domain" do
      user = user_fixture()
      custom_domain = custom_domain_fixture(%{user_id: user.id})

      assert {:ok, %CustomDomain{}} = Domain.delete_custom_domain(custom_domain)

      assert_raise Ecto.NoResultsError, fn ->
        Domain.get_custom_domain!(user, custom_domain.domain)
      end
    end
  end

  describe "dns_record_verified?/2" do
    test "returns true if the DNS record has been verified recently" do
      one_hour_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1 * 60 * 60)
        |> NaiveDateTime.truncate(:second)

      custom_domain =
        custom_domain_fixture(%{
          ownership_verified_at: one_hour_ago
        })

      assert Domain.dns_record_verified?(custom_domain, :ownership_verified_at)
    end

    test "returns false if the DNS record hasn't been verified lately" do
      two_days_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-2 * 60 * 60 * 24)
        |> NaiveDateTime.truncate(:second)

      custom_domain =
        custom_domain_fixture(%{
          dmarc_verified_at: two_days_ago
        })

      refute Domain.dns_record_verified?(custom_domain, :dmarc_verified_at)
    end

    test "returns false if the DNS record hasn't been verified" do
      custom_domain =
        custom_domain_fixture(%{
          dmarc_verified_at: nil
        })

      refute Domain.dns_record_verified?(custom_domain, :dmarc_verified_at)
    end
  end

  describe "fully_verified?/1" do
    test "returns true if all DNS records have been verified recently" do
      one_hour_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1 * 60 * 60)
        |> NaiveDateTime.truncate(:second)

      custom_domain =
        custom_domain_fixture(%{
          ownership_verified_at: one_hour_ago,
          mx_verified_at: one_hour_ago,
          spf_verified_at: one_hour_ago,
          dkim_verified_at: one_hour_ago,
          dmarc_verified_at: one_hour_ago
        })

      assert Domain.fully_verified?(custom_domain)
    end

    test "returns false if any DNS record hasn't been verified lately" do
      one_hour_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1 * 60 * 60)
        |> NaiveDateTime.truncate(:second)

      two_days_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-2 * 60 * 60 * 24)
        |> NaiveDateTime.truncate(:second)

      custom_domain =
        custom_domain_fixture(%{
          ownership_verified_at: one_hour_ago,
          mx_verified_at: one_hour_ago,
          spf_verified_at: one_hour_ago,
          dkim_verified_at: one_hour_ago,
          dmarc_verified_at: two_days_ago
        })

      refute Domain.fully_verified?(custom_domain)
    end

    test "returns false if any DNS record hasn't been verified" do
      one_hour_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1 * 60 * 60)
        |> NaiveDateTime.truncate(:second)

      custom_domain =
        custom_domain_fixture(%{
          ownership_verified_at: nil,
          mx_verified_at: one_hour_ago,
          spf_verified_at: one_hour_ago,
          dkim_verified_at: one_hour_ago,
          dmarc_verified_at: one_hour_ago
        })

      refute Domain.fully_verified?(custom_domain)
    end
  end
end