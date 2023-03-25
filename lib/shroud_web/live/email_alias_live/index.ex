defmodule ShroudWeb.EmailAliasLive.Index do
  import Canada, only: [can?: 2]

  use ShroudWeb, :live_view

  alias Shroud.Accounts
  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Domain
  alias Shroud.Util
  alias Shroud.Repo

  import ShroudWeb.Components.{
    ButtonWithDropdown,
    DropdownItem
  }

  alias ShroudWeb.Components.PopupAlert

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> update_email_aliases()
      |> update_custom_domains()
      |> assign(:filter_query, "")
      |> assign(:custom_alias_domain, nil)
      |> assign(:custom_alias_error, "")
      |> assign(:page_title, "Aliases")
      |> assign(:page_title_url, nil)
      |> assign(:subpage_title, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("add_alias", _params, %{assigns: %{current_user: user}} = socket) do
    if user |> can?(create(EmailAlias)) do
      case Aliases.create_random_email_alias(user) do
        {:ok, email_alias} ->
          socket =
            socket
            |> put_flash(:success, "Created new alias #{email_alias.address}.")
            |> assign(:aliases, [email_alias | socket.assigns.aliases])

          {:noreply,
           push_redirect(socket,
             to: ~p"/alias/#{email_alias.address}"
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
  def handle_event("open_custom_alias_modal", %{"text" => domain}, socket) do
    PopupAlert.show("add_alias_modal")
    {:noreply, assign(socket, :custom_alias_domain, domain)}
  end

  @impl true
  def handle_event(
        "create_custom_alias",
        %{"alias_name" => alias_name},
        %{assigns: %{current_user: user, custom_alias_domain: domain}} = socket
      ) do
    # ensure that the domain belongs to the user
    Repo.get_by!(Domain.CustomDomain, domain: String.trim_leading(domain, "@"), user_id: user.id)
    address = alias_name <> domain

    if user |> can?(create(EmailAlias)) do
      case Aliases.create_email_alias(%{user_id: user.id, address: address}) do
        {:ok, email_alias} ->
          socket
          |> put_flash(:success, "Created new alias #{email_alias.address}.")
          |> assign(:aliases, [email_alias | socket.assigns.aliases])

          {:noreply,
           push_redirect(socket,
             to: ~p"/alias/#{email_alias.address}"
           )}

        {:error, changeset} ->
          {error, _} = Keyword.get(changeset.errors, :address)

          socket =
            socket
            |> assign(:custom_alias_error, error)
            |> put_flash(:error, "Something went wrong.")

          {:noreply, socket}
      end
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

  defp update_custom_domains(socket) do
    domains =
      socket.assigns[:current_user]
      |> Domain.list_custom_domains()
      |> Enum.filter(&Domain.fully_verified?/1)

    assign(
      socket,
      :custom_domains,
      domains
    )
  end
end
