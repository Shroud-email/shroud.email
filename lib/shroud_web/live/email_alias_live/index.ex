defmodule ShroudWeb.EmailAliasLive.Index do
  use Phoenix.HTML
  use ShroudWeb, :live_view
  on_mount ShroudWeb.UserLiveAuth

  alias Shroud.Aliases

  alias ShroudWeb.Components.AliasCard

  @impl true
  def mount(_params, _session, socket) do
    {:ok, update_email_aliases(socket)}
  end

  @impl true
  def handle_event("add_alias", _params, socket) do
    socket =
      case Aliases.create_random_email_alias(socket.assigns[:current_user]) do
        {:ok, _struct} ->
          socket
          |> put_flash(:info, "Created new alias.")

        {:error, _changeset} ->
          socket
          |> put_flash(:error, "Something went wrong.")
      end

    {:noreply, update_email_aliases(socket)}
  end

  @impl true
  def handle_info({:deleted_alias, id}, socket) do
    {:ok, deleted_alias} = Aliases.delete_email_alias(id)

    socket =
      socket
      |> update_email_aliases()
      |> put_flash(:info, "Deleted alias #{deleted_alias.address}.")

    {:noreply, socket}
  end

  defp update_email_aliases(socket) do
    assign(socket, :aliases, Aliases.list_aliases!(socket.assigns[:current_user]))
  end
end
