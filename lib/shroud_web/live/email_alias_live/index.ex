defmodule ShroudWeb.EmailAliasLive.Index do
  import Canada, only: [can?: 2]

  use Phoenix.HTML
  use ShroudWeb, :live_view

  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> update_email_aliases()

    {:ok, socket}
  end

  @impl true
  def handle_event("add_alias", _params, %{assigns: %{current_user: user}} = socket) do
    socket =
      if user |> can?(create(EmailAlias)) do
        case Aliases.create_random_email_alias(user) do
          {:ok, email_alias} ->
            socket
            |> put_flash(:info, "Created new alias #{email_alias.address}.")
            |> assign(:aliases, [email_alias | socket.assigns.aliases])

          {:error, _changeset} ->
            socket
            |> put_flash(:error, "Something went wrong.")
        end
      else
        socket |> put_flash(:error, "You don't have permission to do that.")
      end

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
    assign(socket, :aliases, Aliases.list_aliases(socket.assigns[:current_user]))
  end
end
