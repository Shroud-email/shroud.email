defmodule ShroudWeb.SpamEmailLive.Index do
  import Canada, only: [can?: 2]

  use Phoenix.HTML
  use ShroudWeb, :surface_view
  alias Surface.Components.LiveRedirect

  alias Shroud.Email
  alias Shroud.Aliases

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Spam Detention")
      |> assign(:page_title_url, nil)
      |> assign(:subpage_title, nil)
      |> load_spam_emails()

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    spam_email =
      id
      |> String.to_integer()
      |> Email.get_spam_email!()

    if can?(socket.assigns.current_user, destroy(spam_email)) do
      Email.delete_spam_email!(spam_email)
    end

    {:noreply, load_spam_emails(socket)}
  end

  def handle_event("block_sender", %{"sender" => sender, "alias" => alias_address}, socket) do
    email_alias = Aliases.get_email_alias_by_address!(alias_address)

    if can?(socket.assigns.current_user, update(email_alias)) do
      with {:ok, _alias} <- Aliases.block_sender(email_alias, sender) do
        # re-load spam emails to update associated email_alias' list of blocked senders
        {:noreply, load_spam_emails(socket)}
      end
    end
  end

  defp load_spam_emails(socket) do
    assign(socket, :spam_emails, Email.list_spam_emails(socket.assigns.current_user))
  end
end
