defmodule ShroudWeb.CustomDomainLive.Index do
  use ShroudWeb, :live_view
  alias ShroudWeb.Components.PopupAlert
  alias Shroud.{Accounts, Domain}

  def mount(_params, _session, socket) do
    domains = Domain.list_custom_domains(socket.assigns.current_user)
    paid = Accounts.paid?(socket.assigns.current_user)

    assigns =
      stream(socket, :domains, domains)
      |> assign(:domains_count, length(domains))
      |> assign(:paid, paid)
      |> assign(:page_title, "Domains")
      |> assign(:page_title_url, nil)
      |> assign(:subpage_title, nil)
      |> assign(:error, nil)

    {:ok, assigns}
  end

  def render(assigns) do
    ~H"""
    <%= if not @paid do %>
      <.empty_state
        title="Custom domains"
        description="Custom domains are available on paid plans. Upgrade to create aliases on your own domain."
        icon={:globe_alt}
      >
        <.link href={~p"/settings/billing"} class="btn btn-primary">Upgrade</.link>
      </.empty_state>
    <% else %>
      <%= if @domains_count == 0 do %>
        <.empty_state
          title="Custom domains"
          description="Custom domains let you create aliases on your own domain like alias@yourdomain.com."
          icon={:globe_alt}
        >
          <.button click="open_modal" icon={:plus} text="Add domain" />
        </.empty_state>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 auto-rows-fr">
          <div id="domains" phx-update="stream" class="contents">
            <.link
              :for={{id, domain} <- @streams.domains}
              id={id}
              navigate={~p"/domains/#{domain.domain}"}
              class="rounded bg-white dark:bg-gray-800 shadow-sm dark:shadow-gray-900/50 hover:shadow-lg transition-shadow-sm p-3 overflow-hidden focus:ring focus:ring-indigo-600"
            >
              <h3 class="font-bold flex items-center text-gray-900 dark:text-gray-100">
                {domain.domain}
                <%= if Domain.fully_verified?(domain) do %>
                  <div x-init x-tooltip.raw="Verified" class="ml-2 mt-1">
                    <.icon name={:check_circle} solid class="text-green-500 h-4 w-4" />
                  </div>
                <% else %>
                  <div x-init x-tooltip.raw="Waiting for DNS records" class="ml-2 mt-1">
                    <icon
                      name={:ellipsis_horizontal}
                      solid
                      class="text-gray-500 h-4 w-4 animate-pulse"
                    />
                  </div>
                <% end %>
              </h3>
              <p class="text-sm text-slate-600 dark:text-slate-400">
                Added {Timex.format!(domain.inserted_at, "{D} {Mshort} {YYYY}")}
              </p>
              <div class="flex justify-between">
                <div class="text-sm text-slate-600 dark:text-slate-400 self-end">
                  Catch-all {if domain.catchall_enabled, do: "enabled", else: "disabled"}.
                </div>
                <div class="translate-x-8 translate-y-10 -mt-16">
                  <.icon name={:globe_alt} solid class="text-gray-200 dark:text-gray-700 h-32 w-32" />
                </div>
              </div>
            </.link>
          </div>
          <div class="rounded border-2 border-dashed border-gray-300 dark:border-gray-600 flex p-3 items-center justify-center">
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
              {@error}
            </p>
          </div>
          <:buttons>
            <.button text="Add" type="submit" />
          </:buttons>
        </.live_component>
      </form>
    <% end %>
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
         push_navigate(socket,
           to: ~p"/domains/#{domain}"
         )}

      {:error, :paid_feature} ->
        {:noreply, assign(socket, :error, "Custom domains require a paid plan.")}

      {:error, changeset} ->
        {error, _} = Keyword.get(changeset.errors, :domain)
        {:noreply, assign(socket, :error, error)}
    end
  end
end
