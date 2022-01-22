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
      |> assign(:blocked_sender_error, "")
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
            <div class="flex items-center">
              <h3 class="text-lg leading-6 font-medium text-gray-900">
                <%= @address %>
              </h3>
              <div
                x-data="{ tooltip: 'Copy to clipboard' }"
                class="ml-2"
              >
                <button x-tooltip="tooltip" class="rounded p-1 focus:ring focus:ring-indigo-500" @click={"navigator.clipboard.writeText('#{@address}'); tooltip = 'Copied!'; setTimeout(() => tooltip = 'Copy to clipboard', 1500)"}>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M8 2a1 1 0 000 2h2a1 1 0 100-2H8z" />
                    <path d="M3 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v6h-4.586l1.293-1.293a1 1 0 00-1.414-1.414l-3 3a1 1 0 000 1.414l3 3a1 1 0 001.414-1.414L10.414 13H15v3a2 2 0 01-2 2H5a2 2 0 01-2-2V5zM15 11h2a1 1 0 110 2h-2v-2z" />
                  </svg>
                </button>
              </div>
            </div>
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
              <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
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
              <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
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
            <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">
                <div>Blocked senders</div>
                <div class="mt-1 font-normal">
                  Emails from these addresses won't be forwarded.
                </div>
              </dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <%= if not Enum.empty?(@alias.blocked_addresses) do %>
                  <ul role="list" class="border border-gray-200 rounded-md divide-y divide-gray-200 mb-6">
                    <%= for blocked_sender <- @alias.blocked_addresses do %>
                      <li class="pl-3 pr-4 py-3 flex items-center justify-between text-sm">
                        <div class="w-0 flex-1 flex items-center">
                          <!-- Heroicon name: solid/mail -->
                          <svg xmlns="http://www.w3.org/2000/svg" class="flex-shrink-0 h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                            <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
                            <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
                          </svg>
                          <span class="ml-2 flex-1 w-0 truncate">
                            <%= blocked_sender %>
                          </span>
                        </div>
                        <div class="ml-4 flex-shrink-0">
                          <button
                            phx-click="unblock_sender"
                            phx-value-sender={blocked_sender}
                            type="button"
                            class="font-medium text-indigo-600 hover:text-indigo-500"
                          >
                            Unblock
                          </button>
                        </div>
                      </li>
                    <% end %>
                  </ul>
                <% end %>

                <form phx-submit="block_sender">
                  <div>
                    <label for="sender" class="block text-sm font-medium text-gray-700">Block an address</label>
                    <div class="mt-1 flex rounded-md shadow-sm">
                      <div class="relative flex items-stretch flex-grow focus-within:z-10">
                        <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                          <!-- Heroicon name: solid/ban -->
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M13.477 14.89A6 6 0 015.11 6.524l8.367 8.368zm1.414-1.414L6.524 5.11a6 6 0 018.367 8.367zM18 10a8 8 0 11-16 0 8 8 0 0116 0z" clip-rule="evenodd" />
                          </svg>
                        </div>
                        <input type="email" name="sender" id="sender" class="focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-none rounded-l-md pl-10 sm:text-sm border-gray-300" placeholder="spammer@example.com">
                      </div>
                      <button type="submit" class="-ml-px relative inline-flex items-center space-x-2 px-4 py-2 border border-gray-300 text-sm font-medium rounded-r-md text-gray-700 bg-gray-50 hover:bg-gray-100 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500">
                        <span>Block sender</span>
                      </button>
                    </div>
                  </div>
                  <%= if @blocked_sender_error do %>
                    <span class="invalid-feedback"><%= @blocked_sender_error %></span>
                  <% end %>
                </form>
              </dd>
            </div>
          </dl>
        </div>
      </div>
      <dl class="grid grid-cols-1 gap-5 xl:grid-cols-4 mt-6">
        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-green-700 truncate">
            Emails forwarded (total)
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= @alias.forwarded %>
          </dd>
        </div>

        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-green-700 truncate">
            Emails forwarded (last 30 days)
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= @alias.forwarded_in_last_30_days %>
          </dd>
        </div>

        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-red-800 truncate">
            Emails blocked (total)
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= @alias.blocked %>
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

  @impl true
  def handle_event(
        "unblock_sender",
        %{"sender" => sender},
        %{assigns: %{current_user: user, alias: email_alias}} = socket
      ) do
    socket =
      if user |> can?(update(email_alias)) do
        case Aliases.unblock_sender(email_alias, sender) do
          {:ok, _email_alias} ->
            socket
            |> put_flash(:info, "Unblocked #{sender}.")
            |> update_email_alias()

          :error ->
            put_flash(socket, :error, "Something went wrong.")
        end
      else
        socket |> put_flash(:error, "You don't have permission to do that.")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "block_sender",
        %{"sender" => sender},
        %{assigns: %{current_user: user, alias: email_alias}} = socket
      ) do
    socket =
      if user |> can?(update(email_alias)) do
        case Aliases.block_sender(email_alias, sender) do
          {:ok, _email_alias} ->
            socket
            |> assign(:blocked_sender_error, "")
            |> put_flash(:info, "Blocked #{sender}.")
            |> update_email_alias()

          {:error, changeset} ->
            {error, _} = Keyword.get(changeset.errors, :blocked_addresses)

            socket
            |> assign(:blocked_sender_error, error)
        end
      else
        socket |> put_flash(:error, "You don't have permission to do that.")
      end

    {:noreply, socket}
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
