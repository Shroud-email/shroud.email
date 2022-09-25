defmodule ShroudWeb.CustomDomainLive.Show do
  use ShroudWeb, :surface_view
  alias Phoenix.PubSub
  import Canada, only: [can?: 2]

  alias Shroud.Domain
  alias Shroud.Domain.DnsRecord
  alias Shroud.Domain.DnsChecker
  alias ShroudWeb.Components.{Button, Page, DnsVerification, Toggle, PopupAlert}
  alias ShroudWeb.Router.Helpers, as: Routes

  data domain, :any
  data verifying, :boolean, default: false
  data initially_verified, :boolean

  def mount(%{"domain" => domain}, _session, socket) do
    custom_domain = Domain.get_custom_domain!(socket.assigns.current_user, domain)

    socket =
      socket
      |> assign(:domain, custom_domain)
      |> assign(:initially_verified, Domain.fully_verified?(custom_domain))
      |> assign(:subpage_title, domain)

    {:ok, socket}
  end

  def render(assigns) do
    assigns = assign(assigns, :verified, Domain.fully_verified?(assigns.domain))

    ~F"""
    <Page
      page_title="Domains"
      page_title_url={Routes.custom_domain_index_path(ShroudWeb.Endpoint, :index)}
      subpage_title={@domain.domain}
      {=@flash}
      {=@current_user}
    >
      <h1 class="text-xl font-semibold text-gray-900 mb-3 flex items-center">
        {@domain.domain}
        <div :if={@verified} x-init x-tooltip.raw="DNS records verified" class="ml-1 mt-1">
          <Heroicons.Solid.CheckCircleIcon class="h-5 w-5 text-green-500" />
        </div>
      </h1>
      {#if @verified}
        <div
          x-data={"{ showing: #{@initially_verified}}"}
          x-init="setTimeout(() => showing = true, 0)"
          x-show="showing"
          x-transition:enter="transition ease-in duration-200"
          x-transition:enter-start="opacity-0"
          x-transition:enter-end="opacity-100"
        >
          <p class="mt-2 mb-6 text-sm text-gray-700">
            Your domain is verified and you can create aliases @{@domain.domain}.
          </p>
          <h3 class="font-semibold text-lg text-gray-900 mb-4">Catch-all</h3>
          <div class="bg-white rounded shadow md:rounded-lg ring-1 ring-black ring-opacity-5 p-4 mb-12">
            <div class="flex items-center">
              <Toggle on={@domain.catchall_enabled} click="toggle_catchall" />
              <label class="ml-3 font-semibold text-sm">Catch-all {if @domain.catchall_enabled, do: "enabled", else: "disabled"}.</label>
            </div>
            <p class="text-gray-700 text-sm mt-3">
              When catch-all is on, you don't need to manually create new aliases. The first time an email
              is sent to anything@{@domain.domain}, a new alias will automatically be created.
            </p>
          </div>
        </div>
      {/if}
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
      <h3 class="font-semibold text-lg text-gray-900 mb-4 mt-8">Danger zone</h3>
      <div class="bg-white rounded shadow md:rounded-lg ring-1 ring-black ring-opacity-5 p-4 mb-12">
        <Button
          intent={:danger}
          click="open_delete_modal"
          text="Delete domain"
          icon={Heroicons.Solid.TrashIcon}
        />
      </div>

      <form phx-submit="delete">
        <PopupAlert
          id="delete_warning"
          title={"Delete #{@domain.domain}?"}
          text="Are you sure you want to delete this domain? This will also delete all aliases associated with it, and they cannot be recovered!"
          icon={Heroicons.Outline.TrashIcon}
        >
          <:buttons>
            <Button intent={:danger} text="Delete" type="submit" />
          </:buttons>
        </PopupAlert>
      </form>
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

  def handle_event("toggle_catchall", _value, %{assigns: %{domain: domain}} = socket) do
    domain = Domain.toggle_catchall!(domain)
    verb = if domain.catchall_enabled, do: "Enabled", else: "Disabled"

    socket =
      socket
      |> assign(:domain, domain)
      |> put_flash(:success, "#{verb} catch-all for #{domain.domain}.")

    {:noreply, socket}
  end

  def handle_event("open_delete_modal", _value, socket) do
    PopupAlert.show("delete_warning")
    {:noreply, socket}
  end

  def handle_event("delete", _value, %{assigns: %{current_user: user, domain: domain}} = socket) do
    if user |> can?(destroy(domain)) do
      Domain.delete_custom_domain!(domain)

      socket =
        socket
        |> put_flash(:success, "Deleted #{domain.domain}.")
        |> redirect(to: Routes.custom_domain_index_path(ShroudWeb.Endpoint, :index))

      {:noreply, socket}
    end
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
