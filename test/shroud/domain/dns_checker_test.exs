defmodule Shroud.Domain.DnsCheckerTest do
  use Shroud.DataCase, async: false
  import Mox
  use Oban.Testing, repo: Shroud.Repo
  alias Shroud.Repo
  alias Shroud.Domain.DnsChecker
  import Shroud.DomainFixtures

  setup :verify_on_exit!

  setup do
    Application.put_env(:shroud, :app_domain, "app.shroud.email")
    Application.put_env(:shroud, :email_domain, "fog.shroud.email")
  end

  describe "ownership" do
    test "verifies ownership" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn domain, record_type ->
        if domain == "example.com" and record_type == :txt do
          ["shroud-verify=deadbeef"]
        else
          []
        end
      end)

      domain =
        custom_domain_fixture(%{
          domain: "example.com",
          verification_code: "shroud-verify=deadbeef"
        })

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert domain.ownership_verified_at != nil
    end

    test "un-verifies ownership" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn _, _ -> [] end)

      domain =
        custom_domain_fixture(%{
          domain: "example.com",
          ownership_verified_at: ~N[2022-07-16 00:00:00]
        })

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert is_nil(domain.ownership_verified_at)
    end
  end

  describe "MX records" do
    test "verifies MX records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn domain, record_type ->
        if domain == "example.com" and record_type == :mx do
          [{10, "app.shroud.email"}]
        else
          []
        end
      end)

      domain = custom_domain_fixture(%{domain: "example.com"})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert domain.mx_verified_at != nil
    end

    test "un-verifies MX records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn _, _ -> [] end)

      domain =
        custom_domain_fixture(%{domain: "example.com", mx_verified_at: ~N[2022-07-16 00:00:00]})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert is_nil(domain.mx_verified_at)
    end
  end

  describe "SPF records" do
    test "verifies SPF records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn domain, record_type ->
        if domain == "example.com" and record_type == :txt do
          ["v=spf1 mx ~all"]
        else
          []
        end
      end)

      domain = custom_domain_fixture(%{domain: "example.com"})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert domain.spf_verified_at != nil
    end

    test "un-verifies SPF records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn _, _ -> [] end)

      domain =
        custom_domain_fixture(%{domain: "example.com", spf_verified_at: ~N[2022-07-16 00:00:00]})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert is_nil(domain.spf_verified_at)
    end
  end

  describe "DKIM records" do
    test "verifies DKIM records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn domain, record_type ->
        if domain == "shroudemail._domainkey.example.com" and record_type == :cname do
          ["shroudemail._domainkey.fog.shroud.email"]
        else
          []
        end
      end)

      domain = custom_domain_fixture(%{domain: "example.com"})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert domain.dkim_verified_at != nil
    end

    test "un-verifies DKIM records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn _, _ -> [] end)

      domain =
        custom_domain_fixture(%{domain: "example.com", dkim_verified_at: ~N[2022-07-16 00:00:00]})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert is_nil(domain.dkim_verified_at)
    end
  end

  describe "DMARC records" do
    test "verifies DMARC records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn domain, record_type ->
        if domain == "_dmarc.example.com" and record_type == :txt do
          ["v=DMARC1; p=none; sp=none; aspf=r; adkim=r"]
        else
          []
        end
      end)

      domain = custom_domain_fixture(%{domain: "example.com"})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert domain.dmarc_verified_at != nil
    end

    test "un-verifies DMARC records" do
      Shroud.MockDnsClient
      |> stub(:lookup, fn _, _ -> [] end)

      domain =
        custom_domain_fixture(%{domain: "example.com", dmarc_verified_at: ~N[2022-07-16 00:00:00]})

      perform_job(DnsChecker, %{custom_domain_id: domain.id})

      domain = Repo.reload!(domain)

      assert is_nil(domain.dmarc_verified_at)
    end
  end
end
