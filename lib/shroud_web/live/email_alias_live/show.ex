defmodule ShroudWeb.EmailAliasLive.Show do
  import Canada, only: [can?: 2]
  use ShroudWeb, :surface_view
  alias Shroud.Aliases
  alias Shroud.Email.ReplyAddress
  alias ShroudWeb.Components.{CopyToClipboardButton, Toggle}

  alias Surface.Components.Form
  alias Surface.Components.Form.{Label, TextInput, TextArea}

  @impl true
  def handle_params(%{"address" => address}, _uri, socket) do
    socket =
      socket
      |> assign(:address, address)
      |> assign(:page_title, "Aliases")
      |> assign(:page_title_url, Routes.email_alias_index_path(socket, :index))
      |> assign(:subpage_title, address)
      |> assign(:blocked_sender_error, "")
      |> assign(:reverse_alias_recipient, "")
      |> update_email_alias()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~F"""
    <div>
      <div class="bg-white shadow overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6">
          <div class="flex flex-col sm:flex-row items-center w-full">
            <h3 class="text-lg leading-6 font-medium text-gray-900">
              {@address}
            </h3>
            <CopyToClipboardButton class="ml-2 mt-2 sm:mt-0" text={@address} />
            <div class="hidden sm:block ml-auto">
              <button
                phx-click="delete"
                data-confirm={"Are you sure you want to permanently delete #{@alias.address}?"}
                class="text-xs font-semibold uppercase text-red-700 hover:text-red-500"
              >Delete</button>
            </div>
          </div>
          <div class="flex justify-end sm:justify-between items-center mt-2">
            <button
              phx-click="delete"
              data-confirm={"Are you sure you want to permanently delete #{@alias.address}?"}
              class="sm:hidden text-xs font-semibold uppercase text-red-700 hover:text-red-500"
            >Delete</button>
          </div>
        </div>
        <div class="border-t border-gray-200">
          <dl>
            <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">
                Enabled?
              </dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <Toggle click="toggle" on={@alias.enabled} />
              </dd>
            </div>
            <Form
              for={@changeset}
              submit="update"
              opts={[
                "@submit": "editingNotes = false; editingTitle = false",
                "x-data": "{ editingTitle: false, editingNotes: false }"
              ]}
            >
              <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">
                  <Label field={:title}>Title</Label>
                </dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2 flex">
                  <TextInput
                    field={:title}
                    opts={["x-show": "editingTitle", placeholder: "Alias title"]}
                    class="flex-grow shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
                  />
                  <span x-show="!editingTitle" class="flex-grow">{@alias.title || "No title yet"}</span>
                  <span class="ml-4 flex-shrink-0">
                    <button
                      @click="editingTitle = true"
                      x-show="!editingTitle"
                      type="button"
                      class="bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      Update
                    </button>
                    <button
                      type="submit"
                      x-show="editingTitle"
                      class="bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >Save</button>
                  </span>
                </dd>
              </div>
              <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500">
                  <Label field={:notes}>Notes</Label>
                </dt>
                <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2 flex">
                  <TextArea
                    field={:notes}
                    opts={["x-show": "editingNotes", placeholder: "Notes about this alias"]}
                    class="shadow-sm block w-full focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm border border-gray-300 rounded-md"
                  />
                  <span x-show="!editingNotes" class="flex-grow">{@alias.notes || "No notes"}</span>
                  <span class="ml-4 flex-shrink-0">
                    <button
                      @click="editingNotes = true"
                      x-show="!editingNotes"
                      type="button"
                      class="bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      Update
                    </button>
                    <button
                      type="submit"
                      x-show="editingNotes"
                      class="bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >Save</button>
                  </span>
                </dd>
              </div>
            </Form>
            <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">
                <div>Send emails</div>
                <div class="mt-1 font-normal">
                  Create a reverse alias to send emails from this address.
                </div>
              </dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <form phx-submit="update_recipient">
                  <fieldset class="bg-white">
                    <div class="mt-1 rounded-md shadow-sm -space-y-px">
                      <div class="mt-1 flex rounded-t-md shadow-sm">
                        <div class="relative flex items-stretch flex-grow focus-within:z-10">
                          <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                            <Heroicons.Solid.AtSymbolIcon class="h-5 w-5 text-gray-400" />
                          </div>
                          <input
                            type="email"
                            name="recipient"
                            id="recipient"
                            class="focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-none rounded-tl-md pl-10 sm:text-sm border-gray-300"
                            placeholder="Who do you want to email?"
                          />
                        </div>
                        <button
                          type="submit"
                          class="-ml-px relative inline-flex items-center space-x-2 px-4 py-2 border border-gray-300 text-sm font-medium rounded-tr-md text-gray-700 bg-gray-50 hover:bg-gray-100 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
                        >
                          Generate
                        </button>
                      </div>
                      <div class="rounded-b-md sm:text-sm bg-gray-50 border p-2 border-gray-300 flex items-center">
                        {#if @reverse_alias_recipient == ""}
                          <span class="pl-2">-</span>
                        {#else}
                          {ReplyAddress.to_reply_address(@reverse_alias_recipient, @address)}
                          <CopyToClipboardButton
                            class="ml-2 mt-2 sm:mt-0"
                            text={ReplyAddress.to_reply_address(@reverse_alias_recipient, @address)}
                          />
                        {/if}
                      </div>
                    </div>
                  </fieldset>
                  {#if @reverse_alias_recipient != ""}
                    <p class="mt-3 text-sm text-gray-900">
                      Send an email to the above reverse alias. The recipient you entered will receive your message,
                      but won't be able to see your real email address.
                    </p>
                  {/if}
                </form>
              </dd>
            </div>
            <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">
                <div>Blocked senders</div>
                <div class="mt-1 font-normal">
                  Emails from these addresses won't be forwarded.
                </div>
              </dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                {#if not Enum.empty?(@alias.blocked_addresses)}
                  <ul role="list" class="border border-gray-200 rounded-md divide-y divide-gray-200 mb-6">
                    {#for blocked_sender <- @alias.blocked_addresses}
                      <li class="pl-3 pr-4 py-3 flex items-center justify-between text-sm">
                        <div class="w-0 flex-1 flex items-center">
                          <Heroicons.Solid.MailIcon class="flex-shrink-0 h-5 w-5 text-gray-400" />
                          <span class="ml-2 flex-1 w-0 truncate">
                            {blocked_sender}
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
                    {/for}
                  </ul>
                {/if}

                <form phx-submit="block_sender">
                  <div>
                    <label for="sender" class="sr-only">Block an address</label>
                    <div class="mt-1 flex rounded-md shadow-sm">
                      <div class="relative flex items-stretch flex-grow focus-within:z-10">
                        <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                          <Heroicons.Solid.BanIcon class="h-5 w-5 text-gray-400" />
                        </div>
                        <input
                          type="email"
                          name="sender"
                          id="sender"
                          class="focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-none rounded-l-md pl-10 sm:text-sm border-gray-300"
                          placeholder="spammer@example.com"
                        />
                      </div>
                      <button
                        type="submit"
                        class="-ml-px relative inline-flex items-center space-x-2 px-4 py-2 border border-gray-300 text-sm font-medium rounded-r-md text-gray-700 bg-gray-50 hover:bg-gray-100 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
                      >
                        Block
                      </button>
                    </div>
                  </div>
                  {#if @blocked_sender_error}
                    <span class="invalid-feedback">{@blocked_sender_error}</span>
                  {/if}
                </form>
              </dd>
            </div>
          </dl>
        </div>
      </div>
      <dl class="grid grid-cols-1 gap-5 xl:grid-cols-4 mt-6">
        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-green-700 truncate">
            Emails forwarded
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            {@alias.forwarded}
          </dd>
          <div class="sm:text-sm text-gray-600 ml-1 mt-1">
            {@alias.forwarded_in_last_30_days} in the last month
          </div>
        </div>

        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-green-700 truncate">
            Replies sent
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            {@alias.replied}
          </dd>
          <div class="sm:text-sm text-gray-600 ml-1 mt-1">
            {@alias.replied_in_last_30_days} in the last month
          </div>
        </div>

        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-red-800 truncate">
            Emails blocked
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            {@alias.blocked}
          </dd>
          <div class="sm:text-sm text-gray-600 ml-1 mt-1">
            {@alias.blocked_in_last_30_days} in the last month
          </div>
        </div>

        <div class="px-4 py-5 bg-white shadow rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-gray-500 truncate">
            Created
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            {Timex.format!(@alias.inserted_at, "{D} {Mshort} '{YY}")}
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
        |> put_flash(:success, "Deleted alias #{deleted_alias.address}.")
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
  def handle_event("update_recipient", %{"recipient" => recipient}, socket) do
    {:noreply, assign(socket, reverse_alias_recipient: recipient)}
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
            |> put_flash(:success, "Blocked #{sender}.")
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
