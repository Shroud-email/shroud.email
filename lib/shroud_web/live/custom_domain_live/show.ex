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
      <div class="bg-white px-4 py-5 border-b border-gray-200 sm:px-6">
        <div class="-ml-4 -mt-4 flex justify-between items-center flex-wrap sm:flex-nowrap">
          <div class="ml-4 mt-4">
            <h2 class="text-lg leading-6 font-semibold text-gray-900">{@domain.domain}</h2>
            <p class="mt-1 text-sm text-gray-500">{if Domain.fully_verified?(@domain),
                do: "DNS records verified.",
                else: "Set up your DNS records to use this domain."}</p>
          </div>
          {!--<div class="ml-4 mt-4 flex-shrink-0">
            <button type="button" class="relative inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">Create new job</button>
          </div>--}
        </div>
      </div>

      <div class="mt-6 space-y-3">
        <DnsVerification
          {=@domain}
          {=@verifying}
          verify="verify"
          field={:ownership_verified_at}
          title="Ownership"
          records={DnsRecord.desired_ownership_records(@domain)}
        />
        <DnsVerification
          {=@domain}
          {=@verifying}
          verify="verify"
          field={:mx_verified_at}
          title="MX"
          records={DnsRecord.desired_mx_records(@domain)}
        />
        <DnsVerification
          {=@domain}
          {=@verifying}
          verify="verify"
          field={:spf_verified_at}
          title="SPF"
          records={DnsRecord.desired_spf_records(@domain)}
        />
        <DnsVerification
          {=@domain}
          {=@verifying}
          verify="verify"
          field={:dkim_verified_at}
          title="DKIM"
          records={DnsRecord.desired_dkim_records(@domain)}
        />
        <DnsVerification
          {=@domain}
          {=@verifying}
          verify="verify"
          field={:dmarc_verified_at}
          title="DMARC"
          records={DnsRecord.desired_dmarc_records(@domain)}
        />
      </div>
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
