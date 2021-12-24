defmodule ShroudWeb.EmailAliasLive.Show do
  import Canada, only: [can?: 2]
  use ShroudWeb, :live_view
  alias Shroud.Aliases

  @impl true
  def handle_params(%{"address" => address}, _uri, socket) do
    socket =
      socket
      |> assign(:address, address)
      |> assign(:page_title, "Aliases")
      |> assign(:subpage_title, address)
      |> update_email_alias()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="bg-white shadow overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6 flex justify-between">
          <div>
            <h3 class="text-lg leading-6 font-medium text-gray-900">
              <%= @address %>
            </h3>
            <%= live_redirect to: Routes.email_alias_index_path(@socket, :index), class: "inline-block mt-2 text-sm text-gray-500 hover:text-gray-700" do %>
              <svg xmlns="http://www.w3.org/2000/svg" class="inline h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M9.707 14.707a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 1.414L7.414 9H15a1 1 0 110 2H7.414l2.293 2.293a1 1 0 010 1.414z" clip-rule="evenodd" />
              </svg>
              Back
            <% end %>
          </div>
          <div class="self-start">
            <button phx-click="delete" data-confirm={"Are you sure you want to permanently delete #{@alias.address}?"} class="text-xs font-semibold uppercase text-red-700 hover:text-red-500">Delete</button>
          </div>
        </div>
        <div class="border-t border-gray-200">
          <dl>
            <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">
                Enabled?
              </dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <.toggle phx_click="toggle" enabled={@alias.enabled} />
              </dd>
            </div>
            <.form @submit="editingNotes = false; editingTitle = false" let={f} for={@changeset} phx-submit="update" x-data="{ editingTitle: false, editingNotes: false }">
              <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">
                  Title
                </dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2 flex">
                  <%= label f, :title, "Title", class: "sr-only" %>
                  <%= text_input f, :title, placeholder: "Alias title", "x-show": "editingTitle", class: "flex-grow shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md" %>
                  <span x-show="!editingTitle" class="flex-grow"><%= @alias.title || "No title yet" %></span>
                  <span class="ml-4 flex-shrink-0">
                    <button @click="editingTitle = true" x-show="!editingTitle" type="button" class="bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                      Update
                    </button>
                    <%= submit "Save", "x-show": "editingTitle", class: "bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500" %>
                  </span>
                </dd>
              </div>
              <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">
                  Notes
                </dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2 flex">
                  <%= label f, :notes, "Notes", class: "sr-only" %>
                  <%= textarea f, :notes, placeholder: "Notes about this alias", "x-show": "editingNotes", class: "flex-grow shadow-sm block w-full focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm border border-gray-300 rounded-md" %>
                  <span x-show="!editingNotes" class="flex-grow"><%= @alias.notes || "No notes" %></span>
                  <span class="ml-4 flex-shrink-0">
                    <button @click="editingNotes = true" x-show="!editingNotes" type="button" class="bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                      Update
                    </button>
                    <%= submit "Save", "x-show": "editingNotes", class: "bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500" %>
                  </span>
                </dd>
              </div>
            </.form>
          </dl>
        </div>
      </div>
      <dl class="grid grid-cols-1 gap-5 sm:grid-cols-3 mt-6">
        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-gray-500 truncate">
            Emails forwarded (total)
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= @alias.forwarded %>
          </dd>
        </div>

        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-gray-500 truncate">
            Emails forwarded (last 30 days)
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= @alias.forwarded_in_last_30_days %>
          </dd>
        </div>

        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-gray-500 truncate">
            Created
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= Timex.format!(@alias.inserted_at, "{D} {Mshort} '{YY}") %>
          </dd>
        </div>
      </dl>
    </div>
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
  def handle_event("toggle", _params, %{assigns: %{alias: alias}} = socket) do
    {:noreply, update_alias(socket, %{enabled: !alias.enabled})}
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

    socket
    |> assign(:alias, email_alias)
    |> assign(:changeset, Aliases.change_email_alias(email_alias))
  end
end
