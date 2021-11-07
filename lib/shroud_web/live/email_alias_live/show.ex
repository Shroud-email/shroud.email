defmodule ShroudWeb.EmailAliasLive.Show do
  import Canada, only: [can?: 2]
  use ShroudWeb, :live_view
  alias Shroud.Aliases

  @impl true
  def handle_params(%{"address" => address}, _uri, socket) do
    socket = assign(socket, :address, address)
    {:noreply, update_email_alias(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= live_redirect to: Routes.email_alias_index_path(@socket, :index), class: "link link-hover mb-1 block" do %>
      <svg xmlns="http://www.w3.org/2000/svg" class="inline h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M9.707 14.707a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 1.414L7.414 9H15a1 1 0 110 2H7.414l2.293 2.293a1 1 0 010 1.414z" clip-rule="evenodd" />
      </svg>
      Back
    <% end %>
    <div class="flex flex-col md:flex-row justify-between md:items-center">
      <h1 class="font-extrabold text-xl md:text-3xl"><%= @alias.address %></h1>
      <input id="enabled-toggle" type="checkbox" checked={@alias.enabled} class="toggle toggle-lg tooltip" data-tip="Enabled?" phx-click="toggle" />
    </div>
    <div x-data="{ editing: false }" class="my-3">
      <.form let={f} for={@changeset} class="mt-3 mb-6" x-show="editing" phx-submit="update">
        <div class="form-control">
          <%= label f, :title, "Title", class: "label" %>
          <%= text_input f, :title, placeholder: "Alias title", class: "input input-bordered" %>
        </div>
        <div class="form-control">
          <%= label f, :notes, "Notes", class: "label" %>
          <%= textarea f, :notes, placeholder: "Notes about this alias", class: "textarea textarea-bordered" %>
        </div>
        <%= submit "Save", class: "btn btn-primary mt-2" %>
        <button type="button" @click="editing = false" class="btn btn-ghost">Cancel</button>
      </.form>
      <div x-show="!editing">
        <dl>
          <dt class="font-bold mb-2">Title</dt>
          <dd class="bg-neutral rounded-lg p-3 w-max"><%= @alias.title || "No title" %></dd>
          <dt class="font-bold my-1">Notes</dt>
          <dd class="max-w-md bg-neutral rounded-lg p-3">
            <span class="whitespace-pre"><%= @alias.notes || "No notes yet" %></span>
          </dd>
        </dl>
        <button @click="editing = true" class="mt-2 link link-hover">Edit</button>
      </div>
    </div>
    <div class="stats mb-3 grid-flow-row md:grid-flow-col w-full border border-base-200 shadow">
      <div class="stat">
        <div class="stat-title">Emails forwarded</div>
        <div class="stat-value"><%= @alias.forwarded %></div>
        <div class="stat-desc"><%= @alias.forwarded_in_last_30_days %> in the last 30 days</div>
      </div>
      <div class="stat">
        <div class="stat-title">Created</div>
        <div class="stat-value"><%= Timex.format!(@alias.inserted_at, "{D} {Mshort} '{YY}") %></div>
        <div class="stat-desc"><%= Timex.Format.DateTime.Formatters.Relative.format!(@alias.inserted_at, "{relative}") %></div>
      </div>
    </div>
    <%= link "Delete alias", to: "#", phx_click: "delete", data: [confirm: "Are you sure you want to permanently delete #{@alias.address}?"], class: "btn btn-outline btn-xs btn-error" %>
    """
  end

  def handle_event(
        "delete",
        _params,
        %{assigns: %{current_user: user, alias: email_alias}} = socket
      ) do
    socket =
      if user |> can?(destroy(email_alias)) do
        {:ok, deleted_alias} = Aliases.delete_email_alias(email_alias.id)

        socket
        |> put_flash(:info, "Deleted alias #{deleted_alias.address}.")
        |> push_redirect(to: Routes.email_alias_index_path(socket, :index))
      else
        socket |> put_flash(:error, "You don't have permission to do that.")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle", %{"value" => "on"}, socket) do
    {:noreply, update_alias(socket, %{enabled: true})}
  end

  @impl true
  def handle_event("toggle", %{}, socket) do
    {:noreply, update_alias(socket, %{enabled: false})}
  end

  @impl true
  def handle_event("update", %{"email_alias" => %{"title" => title, "notes" => notes}}, socket) do
    {:noreply, update_alias(socket, %{title: title, notes: notes})}
  end

  defp update_alias(%{assigns: %{current_user: user, alias: email_alias}} = socket, params) do
    if user |> can?(update(email_alias)) do
      case Aliases.update_email_alias(email_alias, params) do
        {:ok, email_alias} ->
          verb =
            case params do
              %{enabled: true} -> "Enabled"
              %{enabled: false} -> "Disabled"
              _other -> "Updated"
            end

          socket
          |> update_email_alias()
          |> put_flash(:info, "#{verb} #{email_alias.address}.")

        {:error, _error} ->
          socket
          |> put_flash(:error, "Something went wrong.")
      end
    else
      socket |> put_flash(:error, "You don't have permission to do that.")
    end
  end

  defp update_email_alias(socket) do
    email_alias = Aliases.get_email_alias_by_address!(socket.assigns.address)

    socket =
      socket
      |> assign(:alias, email_alias)
      |> assign(:changeset, Aliases.change_email_alias(email_alias))
  end
end
