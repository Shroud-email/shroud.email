defmodule ShroudWeb.InboxLive do
  use ShroudWeb, :live_view
  alias Shroud.Inboxes

  @impl true
  def handle_params(%{"address" => address} = params, _uri, socket) do
    user = socket.assigns.current_user

    if Inboxes.enabled?(user) do
      inbox = Inboxes.get_inbox!(user, address)
      page = Inboxes.list_messages(user, address, Map.get(params, "page", "1"))

      socket =
        socket
        |> assign(:page_title, "Inbox")
        |> assign(:page_title_url, ~p"/")
        |> assign(:subpage_title, address)
        |> assign(:inbox, inbox)
        |> assign(:retention_form, to_form(Shroud.Aliases.change_email_alias(inbox)))
        |> assign(:page, page.page_number)
        |> assign(:total_pages, page.total_pages)
        |> stream(:messages, page.entries, reset: true)
        |> assign(:message, nil)
        |> assign(:email, nil)

      socket =
        if params["id"] do
          {message, email} = Inboxes.read_message!(user, params["id"])

          if message.email_alias_id != inbox.id,
            do: raise(Ecto.NoResultsError, queryable: Shroud.Inboxes.Message)

          assign(socket, message: message, email: email)
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    if Inboxes.enabled?(socket.assigns.current_user) do
      handle_inbox_event(event, params, socket)
    else
      {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  defp handle_inbox_event("toggle_read", _params, socket) do
    message = socket.assigns.message
    updated = Inboxes.set_read!(socket.assigns.current_user, message.id, !message.read)
    {:noreply, assign(socket, :message, updated) |> stream_insert(:messages, updated)}
  end

  defp handle_inbox_event("delete", _params, socket) do
    Inboxes.delete_message!(socket.assigns.current_user, socket.assigns.message.id)
    {:noreply, push_patch(socket, to: ~p"/inbox/#{socket.assigns.inbox.address}")}
  end

  defp handle_inbox_event("retention", %{"email_alias" => %{"retention_days" => days}}, socket) do
    case Inboxes.set_retention(socket.assigns.current_user, socket.assigns.inbox.address, days) do
      {:ok, inbox} ->
        {:noreply,
         socket
         |> assign(:inbox, inbox)
         |> assign(:retention_form, to_form(Shroud.Aliases.change_email_alias(inbox)))
         |> put_notification(:success, "Updated retention.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :retention_form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="rounded-lg bg-white dark:bg-gray-800 shadow-sm p-5 space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-gray-100">
            {@inbox.title || @inbox.address}
          </h2>
          <.link
            navigate={~p"/alias/#{@inbox.address}"}
            class="text-sm text-indigo-600 dark:text-indigo-400"
          >
            Alias settings
          </.link>
        </div>
        <p class="text-sm text-gray-600 dark:text-gray-400">
          Mail stays in this inbox. It is not forwarded to your regular email.
        </p>
        <.form for={@retention_form} id="inbox-retention" phx-submit="retention" class="space-y-2">
          <label
            for="retention-days"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300"
          >
            Retention in days
          </label>
          <div class="flex flex-wrap items-center gap-3">
            <input
              id="retention-days"
              type="number"
              min="1"
              max="36500"
              name="email_alias[retention_days]"
              value={@retention_form[:retention_days].value}
              placeholder="Keep forever"
              class="rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
            />
            <.button text="Save retention" type="submit" />
          </div>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            Leave blank to keep emails forever. A shorter period also applies to existing mail. Expired mail and deleted messages are removed from storage hourly.
          </p>
          <p
            :for={{message, _} <- @retention_form[:retention_days].errors}
            class="text-sm text-red-600"
          >
            {message}
          </p>
        </.form>
      </div>
      <section
        aria-label="Messages"
        class="rounded-lg bg-white dark:bg-gray-800 shadow-sm overflow-hidden"
      >
        <div
          id="inbox-messages"
          phx-update="stream"
          class="divide-y divide-gray-200 dark:divide-gray-700"
        >
          <p id="inbox-empty" class="hidden only:block p-6 text-sm text-gray-500 dark:text-gray-400">
            No messages yet.
          </p>
          <.link
            :for={{id, message} <- @streams.messages}
            id={id}
            patch={~p"/inbox/#{@inbox.address}/messages/#{message.id}"}
            class="block p-4 hover:bg-gray-50 dark:hover:bg-gray-700"
          >
            <div class="flex items-center justify-between gap-3">
              <span class={
                if(message.read,
                  do: "text-gray-700 dark:text-gray-300",
                  else: "font-semibold text-gray-900 dark:text-gray-100"
                )
              }>
                {message.subject || "(No subject)"}
              </span>
              <span class="text-xs text-gray-500 dark:text-gray-400">
                {if message.read, do: "Read", else: "Unread"}{if message.spam, do: " · Spam"}
              </span>
            </div>
            <p class="text-sm text-gray-500 dark:text-gray-400 break-all">
              {message.sender} · {Calendar.strftime(message.inserted_at, "%d %b %Y %H:%M UTC")}
            </p>
          </.link>
        </div>
        <nav
          :if={@total_pages > 1}
          aria-label="Message pages"
          class="flex justify-between p-4 text-sm text-indigo-600 dark:text-indigo-400"
        >
          <.link :if={@page > 1} patch={~p"/inbox/#{@inbox.address}?page=#{@page - 1}"}>
            Previous
          </.link>
          <span>Page {@page} of {@total_pages}</span>
          <.link :if={@page < @total_pages} patch={~p"/inbox/#{@inbox.address}?page=#{@page + 1}"}>
            Next
          </.link>
        </nav>
      </section>
      <section
        :if={@message}
        id="inbox-message"
        class="rounded-lg bg-white dark:bg-gray-800 shadow-sm p-5 space-y-4"
      >
        <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100">
          {@message.subject || "(No subject)"}
        </h3>
        <p class="text-sm text-gray-500 dark:text-gray-400">From: {@message.sender}</p>
        <div class="flex gap-3">
          <.button
            id="toggle-read"
            click="toggle_read"
            text={if @message.read, do: "Mark unread", else: "Mark read"}
          />
          <.button
            id="delete-message"
            click="delete"
            text="Delete message"
            intent={:danger_text}
            data-confirm="Delete this message and its attachments?"
          />
        </div>
        <pre
          id="message-body"
          class="whitespace-pre-wrap break-words font-sans text-sm text-gray-800 dark:text-gray-200"
        >{body(@email)}</pre>
        <div :if={@email.attachments != []} id="message-attachments" class="space-y-2">
          <h4 class="text-sm font-semibold text-gray-900 dark:text-gray-100">Attachments</h4>
          <a
            :for={{attachment, index} <- Enum.with_index(@email.attachments)}
            id={"attachment-#{index}"}
            href={~p"/inbox/messages/#{@message.id}/attachments/#{index}"}
            class="block text-sm text-indigo-600 dark:text-indigo-400 break-all"
          >
            {attachment.filename} · {attachment.content_type} · {byte_size(attachment.data)} bytes
          </a>
        </div>
      </section>
    </div>
    """
  end

  defp body(%{text_body: text}) when is_binary(text) and text != "", do: text

  defp body(%{html_body: html}) when is_binary(html) do
    html |> Floki.parse_document!() |> Floki.filter_out("script, style") |> Floki.text(sep: "\n")
  end

  defp body(_), do: ""
end
