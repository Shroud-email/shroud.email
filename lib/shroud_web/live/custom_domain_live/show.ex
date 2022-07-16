defmodule ShroudWeb.CustomDomainLive.Show do
  use Surface.LiveView
  alias Phoenix.PubSub

  alias Shroud.Domain
  alias Shroud.Domain.DnsRecord
  alias Shroud.Domain.DnsChecker
  alias ShroudWeb.Components.{Page, DnsVerification}
  alias ShroudWeb.Router.Helpers, as: Routes

  data domain, :any
  data verifying, :boolean, default: false

  def mount(%{"domain" => domain}, _session, socket) do
    socket =
      socket
      |> assign(:domain, Domain.get_custom_domain!(socket.assigns.current_user, domain))
      |> assign(:subpage_title, domain)

    {:ok, socket}
  end

  def render(assigns) do
    ~F"""
    <Page
      page_title="Domains"
      page_title_url={Routes.custom_domain_index_path(ShroudWeb.Endpoint, :index)}
      subpage_title={@domain.domain}
      {=@flash}
      {=@current_user}
    >
      <DnsVerification
        {=@domain}
        {=@verifying}
        verify="verify"
        sections={[
          Ownership: {:ownership_verified_at, DnsRecord.desired_ownership_records(@domain)},
          MX: {:mx_verified_at, DnsRecord.desired_mx_records(@domain)},
          SPF: {:spf_verified_at, DnsRecord.desired_spf_records(@domain)},
          DKIM: {:dkim_verified_at, DnsRecord.desired_dkim_records(@domain)},
          DMARC: {:dmarc_verified_at, DnsRecord.desired_dmarc_records(@domain)}
        ]}
      />
    </Page>
    """
  end

  def handle_event("verify", _value, socket) do
    PubSub.subscribe(Shroud.PubSub, "dns_checker")

    %{custom_domain_id: socket.assigns.domain.id}
    |> DnsChecker.new()
    |> Oban.insert!()

    {:noreply, assign(socket, :verifying, true)}
  end

  def handle_info(:dns_check_complete, socket) do
    socket =
      socket
      |> assign(
        :domain,
        Domain.get_custom_domain!(socket.assigns.current_user, socket.assigns.domain.domain)
      )
      |> assign(:verifying, false)

    socket =
      if Domain.fully_verified?(socket.assigns.domain) do
        socket
        |> put_flash(:success, "DNS records verified.")
      else
        socket
        |> put_flash(
          :error,
          "Some DNS records are still missing. DNS propagation may take up to 24 hours."
        )
      end

    {:noreply, socket}
  end
end
