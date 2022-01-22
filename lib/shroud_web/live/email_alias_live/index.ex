defmodule ShroudWeb.EmailAliasLive.Index do
  import Canada, only: [can?: 2]

  use Phoenix.HTML
  use ShroudWeb, :live_view

  alias Shroud.Accounts
  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias
  alias ShroudWeb.Router.Helpers, as: Routes

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> update_email_aliases()
      |> assign(:page_title, "Aliases")
      |> assign(:subpage_title, nil)
      |> assign(:filter_query, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("add_alias", _params, %{assigns: %{current_user: user}} = socket) do
    if user |> can?(create(EmailAlias)) do
      case Aliases.create_random_email_alias(user) do
        {:ok, email_alias} ->
          socket =
            socket
            |> put_flash(:info, "Created new alias #{email_alias.address}.")
            |> assign(:aliases, [email_alias | socket.assigns.aliases])

          {:noreply,
           push_redirect(socket,
             to: Routes.email_alias_show_path(socket, :show, email_alias.address)
           )}

        {:error, _changeset} ->
          socket =
            socket
            |> put_flash(:error, "Something went wrong.")

          {:noreply, socket}
      end
    else
      socket = socket |> put_flash(:error, "You don't have permission to do that.")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:filter_query, query)
      |> update_email_aliases()

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:updated_alias, email_alias, params},
        %{assigns: %{current_user: user}} = socket
      ) do
    socket =
      if user |> can?(update(email_alias)) do
        case Aliases.update_email_alias(email_alias, params) do
          {:ok, email_alias} ->
            verb = if email_alias.enabled, do: "Enabled", else: "Disabled"

            socket
            |> assign(:email_alias, email_alias)
            |> put_flash(:info, "#{verb} #{email_alias.address}.")

          {:error, _error} ->
            socket
            |> put_flash(:error, "Something went wrong.")
        end
      else
        socket |> put_flash(:error, "You don't have permission to do that.")
      end

    {:noreply, socket}
  end

  defp update_email_aliases(socket) do
    assign(
      socket,
      :aliases,
      Aliases.list_aliases(socket.assigns[:current_user], socket.assigns[:filter_query])
    )
  end
end
