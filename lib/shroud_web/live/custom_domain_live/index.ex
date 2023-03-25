defmodule ShroudWeb.CustomDomainLive.Index do
  use ShroudWeb, :live_view
  alias ShroudWeb.Components.PopupAlert
  alias Shroud.Domain
  alias ShroudWeb.Router.Helpers, as: Routes

  def mount(_params, _session, socket) do
    domains = Domain.list_custom_domains(socket.assigns.current_user)

    assigns =
      assign(socket, :domains, domains)
      |> assign(:page_title, "Domains")
      |> assign(:page_title_url, nil)
      |> assign(:subpage_title, nil)
      |> assign(:error, nil)

    {:ok, assigns}
  end

  def render(assigns) do
    ~H"""
    <%= if Enum.empty?(@domains) do %>
      <.empty_state
        title="Custom domains"
        description="Custom domains let you create aliases on your own domain like alias@yourdomain.com."
        icon={:globe_alt}
      >
        <.button click="open_modal" icon={:plus} text="Add domain" />
      </.empty_state>
    <% else %>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 auto-rows-fr">
        <.link
          :for={domain <- @domains}
          navigate={Routes.custom_domain_show_path(ShroudWeb.Endpoint, :show, domain.domain)}
          class="rounded bg-white shadow hover:shadow-lg transition-shadow p-3 overflow-hidden focus:ring focus:ring-indigo-600"
        >
          <h3 class="font-bold flex items-center">
            <%= domain.domain %>
            <%= if Domain.fully_verified?(domain) do %>
              <div x-init x-tooltip.raw="Verified" class="ml-2 mt-1">
                <.icon name={:check_circle} solid class="text-green-500 h-4 w-4" />
              </div>
            <% else %>
              <div x-init x-tooltip.raw="Waiting for DNS records" class="ml-2 mt-1">
                <icon name={:ellipsis_horizontal} solid class="text-gray-500 h-4 w-4 animate-pulse" />
              </div>
            <% end %>
          </h3>
          <p class="text-sm text-slate-600">Added <%= Timex.format!(domain.inserted_at, "{D} {Mshort} {YYYY}") %></p>
          <div class="flex justify-between">
            <div class="text-sm text-slate-600 self-end">
              Catch-all <%= if domain.catchall_enabled, do: "enabled", else: "disabled" %>.
            </div>
            <div class="translate-x-8 translate-y-10 -mt-16">
              <.icon name={:globe_alt} solid class="text-gray-200 h-32 w-32" />
            </div>
          </div>
        </.link>
        <div class="rounded border-2 border-dashed border-gray-300 flex p-3 items-center justify-center">
          <.button click="open_modal" icon={:plus} text="Add domain" />
        </div>
      </div>
    <% end %>

    <form phx-submit="create">
      <.live_component
        module={PopupAlert}
        id="add_domain_modal"
        title="Add custom domain"
        text="Enter your domain to get started."
        icon={:globe_alt}
      >
        <div class="mt-2">
          <.text_input name="domain" placeholder="example.com" />
          <p :if={@error} class="text-red-600 mt-1 text-sm">
            <%= @error %>
          </p>
        </div>
        <:buttons>
          <.button text="Add" type="submit" />
        </:buttons>
      </.live_component>
    </form>
    """
  end

  def handle_event("open_modal", _value, socket) do
    PopupAlert.show("add_domain_modal")
    {:noreply, socket}
  end

  def handle_event("create", %{"domain" => domain}, socket) do
    case Domain.create_custom_domain(socket.assigns.current_user, %{domain: domain}) do
      {:ok, _domain} ->
        {:noreply,
         push_redirect(socket,
           to: Routes.custom_domain_show_path(ShroudWeb.Endpoint, :show, domain)
         )}

      {:error, changeset} ->
        {error, _} = Keyword.get(changeset.errors, :domain)
        {:noreply, assign(socket, :error, error)}
    end
  end
end
