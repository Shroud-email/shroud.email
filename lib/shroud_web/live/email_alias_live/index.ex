defmodule ShroudWeb.EmailAliasLive.Index do
  import Canada, only: [can?: 2]

  use Phoenix.HTML
  use ShroudWeb, :live_view
  on_mount ShroudWeb.UserLiveAuth

  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias

  alias ShroudWeb.Components.AliasCard

  @impl true
  def mount(_params, _session, socket) do
    {:ok, update_email_aliases(socket)}
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
  def handle_info({:deleted_alias, id}, %{assigns: %{current_user: user}} = socket) do
    email_alias = Aliases.get_email_alias!(id)

    socket =
      if user |> can?(destroy(email_alias)) do
        {:ok, deleted_alias} = Aliases.delete_email_alias(id)

        socket
        |> update_email_aliases()
        |> put_flash(:info, "Deleted alias #{deleted_alias.address}.")
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
            |> assign(:changeset, Aliases.change_email_alias(email_alias, params))
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
