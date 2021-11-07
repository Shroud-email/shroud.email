defmodule ShroudWeb.Components.AliasCard do
  use Phoenix.HTML
  use ShroudWeb, :live_component

  alias Shroud.Aliases

  @impl true
  def render(assigns) do
    ~H"""
    <article id={"alias-#{@email_alias.id}"} class="card bordered">
      <div class="card-body grid grid-cols-1 md:grid-cols-2">
        <div class="flex items-center">
          <div>
            <div class="text-gray-300"><%= @email_alias.title %></div>
            <div class="font-bold text-lg flex">
              <%= @email_alias.address %>
              <div
                x-data="{ tooltip: 'Copy to clipboard' }"
                :data-tip="tooltip"
                class="tooltip ml-2 flex items-center justify-center"
              >
                <button
                  @click={"navigator.clipboard.writeText('#{@email_alias.address}'); tooltip = 'Copied!'; setTimeout(() => tooltip = 'Copy to clipboard', 1500)"}
                  class="btn btn-xs btn-square btn-ghost"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M8 2a1 1 0 000 2h2a1 1 0 100-2H8z" />
                    <path d="M3 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v6h-4.586l1.293-1.293a1 1 0 00-1.414-1.414l-3 3a1 1 0 000 1.414l3 3a1 1 0 001.414-1.414L10.414 13H15v3a2 2 0 01-2 2H5a2 2 0 01-2-2V5zM15 11h2a1 1 0 110 2h-2v-2z" />
                  </svg>
                </button>
              </div>
              </div>
            </div>
          </div>
        <div class="flex sm:mt-0 justify-end items-center">
          <input type="checkbox" checked={@email_alias.enabled} class="toggle tooltip" data-tip="Enabled?" phx-click="toggle" phx-target={@myself} />
        </div>
        <%= live_redirect to: Routes.email_alias_show_path(@socket, :show, @email_alias.address), class: "link link-hover w-max mt-1" do %>
          Details
          <svg xmlns="http://www.w3.org/2000/svg" class="inline h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10.293 5.293a1 1 0 011.414 0l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414-1.414L12.586 11H5a1 1 0 110-2h7.586l-2.293-2.293a1 1 0 010-1.414z" clip-rule="evenodd" />
          </svg>
        <% end %>
      </div>
    </article>
    """
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
