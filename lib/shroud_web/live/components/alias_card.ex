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
