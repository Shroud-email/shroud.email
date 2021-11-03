defmodule ShroudWeb.Components.AliasCard do
  use Phoenix.HTML
  use ShroudWeb, :live_component

  alias Shroud.Aliases

  @impl true
  def render(assigns) do
    ~H"""
    <article id={"alias-#{@email_alias.id}"} class="card bordered">
      <div class="card-body flex flex-col sm:flex-row justify-between">
        <div class="font-bold text-lg flex items-center">
          <%= @email_alias.address %>
          <div
            x-data="{ tooltip: 'Copy to clipboard' }"
            :data-tip="tooltip"
            @click.away="tooltip = 'Copy to clipboard'"
            class="tooltip ml-2 flex items-center justify-center"
          >
            <button class="btn btn-xs btn-square btn-ghost" @click={"navigator.clipboard.writeText('#{@email_alias.address}'); tooltip = 'Copied!'"}>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M8 2a1 1 0 000 2h2a1 1 0 100-2H8z" />
                <path d="M3 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v6h-4.586l1.293-1.293a1 1 0 00-1.414-1.414l-3 3a1 1 0 000 1.414l3 3a1 1 0 001.414-1.414L10.414 13H15v3a2 2 0 01-2 2H5a2 2 0 01-2-2V5zM15 11h2a1 1 0 110 2h-2v-2z" />
              </svg>
            </button>
          </div>
        </div>
        <div class="flex mt-2 sm:mt-0 justify-end">
          <%= link "Delete", to: "#", phx_click: "delete", phx_target: @myself, data: [confirm: "Are you sure you want to permanently delete #{@email_alias.address}?"], class: "btn btn-outline btn-xs btn-error" %>
          <input type="checkbox" checked={@email_alias.enabled} class="toggle tooltip ml-2" data-tip="Enabled?" phx-click="toggle" phx-target={@myself} />
        </div>
      </div>
    </article>
    """
  end

  @impl true
  def handle_event("delete", _params, socket) do
    send(self(), {:deleted_alias, socket.assigns.email_alias.id})
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "toggle",
        %{"email_alias" => params},
        socket
      ) do
    send(self(), {:updated_alias, socket.assigns.email_alias, params})

    {:noreply,
     assign(socket, :changeset, Aliases.change_email_alias(socket.assigns.email_alias, params))}
  end

  @impl true
  def handle_event("toggle", %{"value" => "on"}, socket) do
    send(self(), {:updated_alias, socket.assigns.email_alias, %{enabled: true}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle", %{}, socket) do
    send(self(), {:updated_alias, socket.assigns.email_alias, %{enabled: false}})
    {:noreply, socket}
  end
end
