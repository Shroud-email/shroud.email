defmodule ShroudWeb.EmailAliasLive.Show do
  import Canada, only: [can?: 2]
  use ShroudWeb, :live_view
  alias Shroud.{Accounts, Aliases}
  alias Shroud.Email.ReplyAddress
  alias ShroudWeb.Components.PopupAlert

  import ShroudWeb.Components.CopyToClipboardButton

  @impl true
  def handle_params(%{"address" => address}, _uri, socket) do
    socket =
      socket
      |> assign(:page_title, "Aliases")
      |> assign(:page_title_url, ~p"/")
      |> assign(:subpage_title, address)
      |> assign(:address, address)
      |> assign(:blocked_sender_error, "")
      |> assign(:reverse_alias_recipient, "")
      |> assign(:inboxes_enabled, Shroud.Inboxes.enabled?(socket.assigns.current_user))
      |> assign(:paid, Accounts.paid?(socket.assigns.current_user))
      |> update_email_alias()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={PopupAlert}
        id="delete-alias-modal"
        title="Delete alias?"
        text={"Are you sure you want to permanently delete #{@alias.address}?"}
        icon={:trash}
      >
        <:buttons>
          <.button id="confirm-delete-alias" intent={:danger} text="Delete" click="delete" />
        </:buttons>
      </.live_component>
      <div class="bg-white dark:bg-gray-800 shadow-sm dark:shadow-gray-900/50 overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6">
          <div class="flex flex-col sm:flex-row items-center w-full">
            <h3 class="text-lg leading-6 font-medium text-gray-900 dark:text-gray-100">
              {@address}
            </h3>
            <.copy_to_clipboard_button
              id="copy-alias-address"
              class="ml-1 mt-2 sm:mt-0"
              text={@address}
            />
            <div class="hidden sm:block ml-auto">
              <.button
                id="delete-alias-desktop"
                click="open_delete_modal"
                intent={:danger_text}
                class="text-xs font-semibold uppercase"
                text="Delete"
              />
            </div>
          </div>
          <div class="flex justify-end sm:justify-between items-center mt-2">
            <.button
              id="delete-alias-mobile"
              click="open_delete_modal"
              intent={:danger_text}
              class="sm:hidden text-xs font-semibold uppercase"
              text="Delete"
            />
          </div>
        </div>
        <div class="border-t border-gray-200 dark:border-gray-700">
          <div :if={@inboxes_enabled and @alias.delivery_mode == :inbox} class="px-4 py-5 sm:px-6">
            <.link
              id="open-inbox"
              navigate={~p"/inbox/#{@alias.address}"}
              class="text-indigo-600 dark:text-indigo-400"
            >
              Open inbox · messages are stored, not forwarded
            </.link>
          </div>
          <dl>
            <div class="bg-gray-50 dark:bg-gray-700 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                Enabled?
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100 sm:mt-0 sm:col-span-2">
                <.toggle click="toggle" on={@alias.enabled} />
              </dd>
            </div>
            <.form
              :let={f}
              for={@changeset}
              phx-submit="update"
              x-on:submit="editingNotes = false; editingTitle = false"
              x-data="{ editingTitle: false, editingNotes: false }"
            >
              <div class="bg-white dark:bg-gray-800 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                  {label(f, :title)}
                </dt>
                <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100 sm:mt-0 sm:col-span-2 flex">
                  {text_input(f, :title,
                    "x-show": "editingTitle",
                    placeholder: "Alias title",
                    class:
                      "grow shadow-xs focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400 rounded-md"
                  )}
                  <span x-show="!editingTitle" class="grow">
                    {@alias.title || "No title yet"}
                  </span>
                  <span class="ml-4 shrink-0">
                    <.button
                      alpine_click="editingTitle = true"
                      x-show="!editingTitle"
                      intent={:text}
                      text="Update"
                    />
                    <.button
                      type="submit"
                      x-show="editingTitle"
                      intent={:text}
                      text="Save"
                    />
                  </span>
                </dd>
              </div>
              <div class="bg-gray-50 dark:bg-gray-700 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                  {label(f, :notes)}
                </dt>
                <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100 sm:mt-0 sm:col-span-2 flex">
                  {textarea(f, :notes,
                    "x-show": "editingNotes",
                    placeholder: "Notes about this alias",
                    class:
                      "shadow-xs block w-full focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm border border-gray-300 dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400 rounded-md"
                  )}
                  <span x-show="!editingNotes" class="grow">
                    {@alias.notes || "No notes"}
                  </span>
                  <span class="ml-4 shrink-0">
                    <.button
                      alpine_click="editingNotes = true"
                      x-show="!editingNotes"
                      intent={:text}
                      text="Update"
                    />
                    <.button
                      type="submit"
                      x-show="editingNotes"
                      intent={:text}
                      text="Save"
                    />
                  </span>
                </dd>
              </div>
            </.form>
            <%= if @paid and @alias.delivery_mode == :forward do %>
              <div class="bg-white dark:bg-gray-800 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
                <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                  <div>Send emails</div>
                  <div class="mt-1 font-normal">
                    Create a reverse alias to send emails from this address.
                  </div>
                </dt>
                <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100 sm:mt-0 sm:col-span-2">
                  <form phx-submit="update_recipient">
                    <fieldset class="bg-white dark:bg-gray-800">
                      <div class="mt-1 rounded-button shadow-xs -space-y-px">
                        <div class="mt-1 flex rounded-t-button shadow-xs">
                          <div class="relative flex items-stretch grow focus-within:z-10">
                            <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                              <.icon name={:at_symbol} solid class="h-5 w-5 text-gray-400" />
                            </div>
                            <input
                              type="email"
                              name="recipient"
                              id="recipient"
                              class="focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-none rounded-tl-button pl-10 sm:text-sm border-gray-300 dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400"
                              placeholder="Who do you want to email?"
                            />
                          </div>
                          <.button
                            type="submit"
                            intent={:white}
                            shape={:top_right}
                            class="-ml-px relative"
                            text="Generate"
                          />
                        </div>
                        <div class="rounded-b-button sm:text-sm bg-gray-50 dark:bg-gray-700 border p-2 border-gray-300 dark:border-gray-600 dark:text-gray-100 flex items-center">
                          <%= if @reverse_alias_recipient == "" do %>
                            <span class="pl-2">-</span>
                          <% else %>
                            {ReplyAddress.to_reply_address(@reverse_alias_recipient, @address)}
                            <.copy_to_clipboard_button
                              id="copy-reverse-alias"
                              class="ml-1 mt-2 sm:mt-0"
                              text={ReplyAddress.to_reply_address(@reverse_alias_recipient, @address)}
                            />
                          <% end %>
                        </div>
                      </div>
                    </fieldset>
                    <p
                      :if={@reverse_alias_recipient != ""}
                      class="mt-3 text-sm text-gray-900 dark:text-gray-100"
                    >
                      Send an email to the above reverse alias. The recipient you entered will receive your message,
                      but won't be able to see your real email address.
                    </p>
                  </form>
                </dd>
              </div>
            <% else %>
              <div
                :if={@alias.delivery_mode == :forward}
                class="bg-white dark:bg-gray-800 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6"
              >
                <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                  <div>Send emails</div>
                </dt>
                <dd class="mt-1 text-sm text-gray-500 dark:text-gray-400 sm:mt-0 sm:col-span-2">
                  Sending emails from aliases requires a paid plan.
                  <.link
                    href={~p"/settings/billing"}
                    class="text-indigo-600 dark:text-indigo-400 hover:text-indigo-500 underline"
                  >
                    Upgrade
                  </.link>
                </dd>
              </div>
            <% end %>
            <div class="bg-white dark:bg-gray-800 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                <div>Blocked senders</div>
                <div class="mt-1 font-normal">
                  Emails from these addresses won't be forwarded.
                </div>
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100 sm:mt-0 sm:col-span-2">
                <ul
                  :if={not Enum.empty?(@alias.blocked_addresses)}
                  role="list"
                  class="border border-gray-200 dark:border-gray-700 rounded-md divide-y divide-gray-200 dark:divide-gray-700 mb-6"
                >
                  <li
                    :for={blocked_sender <- @alias.blocked_addresses}
                    class="pl-3 pr-4 py-3 flex items-center justify-between text-sm"
                  >
                    <div class="w-0 flex-1 flex items-center">
                      <.icon name={:envelope} solid class="shrink-0 h-5 w-5 text-gray-400" />
                      <span class="ml-2 flex-1 w-0 truncate">
                        {blocked_sender}
                      </span>
                    </div>
                    <div class="ml-4 shrink-0">
                      <.button
                        click="unblock_sender"
                        phx-value-sender={blocked_sender}
                        intent={:text}
                        text="Unblock"
                      />
                    </div>
                  </li>
                </ul>

                <form phx-submit="block_sender">
                  <div>
                    <label for="sender" class="sr-only">Block an address</label>
                    <div class="mt-1 flex rounded-button shadow-xs">
                      <div class="relative flex items-stretch grow focus-within:z-10">
                        <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                          <.icon name={:no_symbol} solid class="h-5 w-5 text-gray-400" />
                        </div>
                        <input
                          type="email"
                          name="sender"
                          id="sender"
                          class="focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-none rounded-l-button pl-10 sm:text-sm border-gray-300 dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400"
                          placeholder="spammer@example.com"
                        />
                      </div>
                      <.button
                        type="submit"
                        intent={:white}
                        shape={:right}
                        class="-ml-px relative"
                        text="Block"
                      />
                    </div>
                  </div>
                  <span :if={@blocked_sender_error} class="invalid-feedback">
                    {@blocked_sender_error}
                  </span>
                </form>
              </dd>
            </div>
          </dl>
        </div>
      </div>
      <dl class="grid grid-cols-1 gap-5 xl:grid-cols-4 mt-6">
        <div class="px-4 py-5 bg-white dark:bg-gray-800 shadow-sm dark:shadow-gray-900/50 rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-green-700 dark:text-green-300 truncate">
            Emails forwarded
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-gray-100">
            {@alias.forwarded}
          </dd>
          <div class="sm:text-sm text-gray-600 dark:text-gray-400 ml-1 mt-1">
            {@alias.forwarded_in_last_30_days} in the last month
          </div>
        </div>

        <div class="px-4 py-5 bg-white dark:bg-gray-800 shadow-sm dark:shadow-gray-900/50 rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-green-700 dark:text-green-300 truncate">
            Replies sent
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-gray-100">
            {@alias.replied}
          </dd>
          <div class="sm:text-sm text-gray-600 dark:text-gray-400 ml-1 mt-1">
            {@alias.replied_in_last_30_days} in the last month
          </div>
        </div>

        <div class="px-4 py-5 bg-white dark:bg-gray-800 shadow-sm dark:shadow-gray-900/50 rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-red-800 dark:text-red-300 truncate">
            Emails blocked
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-gray-100">
            {@alias.blocked}
          </dd>
          <div class="sm:text-sm text-gray-600 dark:text-gray-400 ml-1 mt-1">
            {@alias.blocked_in_last_30_days} in the last month
          </div>
        </div>

        <div class="px-4 py-5 bg-white dark:bg-gray-800 shadow-sm dark:shadow-gray-900/50 rounded-lg overflow-hidden sm:p-6">
          <dt class="text-sm font-medium text-gray-500 dark:text-gray-400 truncate">
            Created
          </dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900 dark:text-gray-100">
            {Timex.format!(@alias.inserted_at, "{D} {Mshort} '{YY}")}
          </dd>
        </div>
      </dl>
    </div>
    """
  end

  def handle_event("open_delete_modal", _params, socket) do
    PopupAlert.show("delete-alias-modal")
    {:noreply, socket}
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
        |> put_notification(:success, "Deleted alias #{deleted_alias.address}.")
        |> push_navigate(to: ~p"/")
      else
        socket |> put_notification(:error, "You don't have permission to do that.")
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
            |> put_notification(:info, "Unblocked #{sender}.")
            |> update_email_alias()

          :error ->
            put_notification(socket, :error, "Something went wrong.")
        end
      else
        socket |> put_notification(:error, "You don't have permission to do that.")
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
            |> put_notification(:success, "Blocked #{sender}.")
            |> update_email_alias()

          {:error, changeset} ->
            {error, _} = Keyword.get(changeset.errors, :blocked_addresses)

            socket
            |> assign(:blocked_sender_error, error)
        end
      else
        socket |> put_notification(:error, "You don't have permission to do that.")
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
          |> put_notification(:info, "#{verb} #{email_alias.address}.")

        {:error, _error} ->
          socket
          |> put_notification(:error, "Something went wrong.")
      end
    else
      socket |> put_notification(:error, "You don't have permission to do that.")
    end
  end

  defp update_email_alias(socket) do
    email_alias = Aliases.get_email_alias_by_address!(socket.assigns.address)

    socket
    |> assign(:alias, email_alias)
    |> assign(:changeset, Aliases.change_email_alias(email_alias))
  end
end
