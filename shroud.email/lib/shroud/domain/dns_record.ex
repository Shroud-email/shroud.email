defmodule Shroud.Domain.DnsRecord do
  @type dns_type :: :txt | :mx | :cname
  @type dns_record :: %{
          type: dns_type,
          domain: String.t(),
          value: String.t(),
          priority: integer() | nil
        }

  alias Shroud.Domain.CustomDomain

  @spec desired_ownership_records(CustomDomain.t()) :: [dns_record]
  def desired_ownership_records(%CustomDomain{} = domain) do
    [
      %{
        type: :txt,
        domain: domain.domain,
        value: domain.verification_code,
        priority: nil
      }
    ]
  end

  @spec desired_mx_records(CustomDomain.t()) :: [dns_record]
  def desired_mx_records(%CustomDomain{} = domain) do
    app_domain = Application.fetch_env!(:shroud, :app_domain)

    [
      %{
        type: :mx,
        domain: domain.domain,
        value: app_domain,
        priority: 10
      }
    ]
  end

  @spec desired_spf_records(CustomDomain.t()) :: [dns_record]
  def desired_spf_records(%CustomDomain{} = domain) do
    [
      %{
        type: :txt,
        domain: domain.domain,
        value: "v=spf1 mx ~all",
        priority: nil
      }
    ]
  end

  @spec desired_dkim_records(CustomDomain.t()) :: [dns_record]
  def desired_dkim_records(%CustomDomain{} = domain) do
    email_domain = Application.fetch_env!(:shroud, :email_domain)

    [
      %{
        type: :cname,
        domain: "shroudemail._domainkey.#{domain.domain}",
        value: "shroudemail._domainkey.#{email_domain}",
        priority: nil
      }
    ]
  end

  @spec desired_dmarc_records(CustomDomain.t()) :: [dns_record]
  def desired_dmarc_records(%CustomDomain{} = domain) do
    [
      %{
        type: :txt,
        domain: "_dmarc.#{domain.domain}",
        value: "v=DMARC1; p=none; sp=none; aspf=r; adkim=r",
        priority: nil
      }
    ]
  end
end
