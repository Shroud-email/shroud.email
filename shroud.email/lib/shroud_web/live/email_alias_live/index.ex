defmodule ShroudWeb.EmailAliasLive.Index do
  import Canada, only: [can?: 2]

  use ShroudWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Domain
  alias Shroud.Util
  alias Shroud.Repo

  import ShroudWeb.Components.{
    ButtonWithDropdown,
    CopyToClipboardButton,
    DropdownItem
  }

  alias ShroudWeb.Components.PopupAlert

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> update_custom_domains()
      |> assign(:custom_alias_domain, nil)
      |> assign(:custom_alias_error, "")
      |> assign(:inboxes_enabled, Shroud.Inboxes.enabled?(socket.assigns.current_user))
      |> assign(:alias_count, Aliases.count_aliases(socket.assigns.current_user))
      |> assign_at_free_limit()
      |> assign(:page_title, "Aliases")
      |> assign(:page_title_url, nil)
      |> assign(:subpage_title, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query =
      case params["query"] do
        value when is_binary(value) -> value
        _ -> ""
      end

    page_number = parse_page(params["page"])
    page = Aliases.paginate_aliases(socket.assigns.current_user, query, page_number)

    socket =
      socket
      |> assign(:filter_query, query)
      |> assign(:filtered_alias_count, page.total_entries)
      |> assign(:page_number, page.page_number)
      |> assign(:page_size, page.page_size)
      |> assign(:total_pages, page.total_pages)
      |> assign(:pagination_pages, pagination_pages(page.page_number, page.total_pages))
      |> stream(:aliases, page.entries, reset: true)

    socket =
      if params["page"] && params["page"] != Integer.to_string(page.page_number) do
        push_patch(socket, to: aliases_path(page.page_number, query), replace: true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_inbox", _params, %{assigns: %{current_user: user}} = socket) do
    if Shroud.Inboxes.enabled?(user) and can?(user, create(EmailAlias)) do
      case Aliases.create_random_email_alias(user, %{delivery_mode: :inbox}) do
        {:ok, inbox} -> {:noreply, push_navigate(socket, to: ~p"/inbox/#{inbox.address}")}
        {:error, _} -> {:noreply, put_notification(socket, :error, "Could not create inbox.")}
      end
    else
      {:noreply, put_notification(socket, :error, "You don't have permission to do that.")}
    end
  end

  def handle_event("add_alias", _params, %{assigns: %{current_user: user}} = socket) do
    if user |> can?(create(EmailAlias)) do
      case Aliases.create_random_email_alias(user) do
        {:ok, email_alias} ->
          socket =
            socket
            |> put_notification(:success, "Created new alias #{email_alias.address}.")

          {:noreply,
           push_navigate(socket,
             to: ~p"/alias/#{email_alias.address}"
           )}

        {:error, _changeset} ->
          socket =
            socket
            |> put_notification(:error, "Something went wrong.")

          {:noreply, socket}
      end
    else
      socket = socket |> put_notification(:error, "You don't have permission to do that.")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_custom_alias_modal", %{"text" => domain}, socket) do
    PopupAlert.show("add_alias_modal")

    {:noreply, assign(socket, custom_alias_domain: domain, custom_alias_error: "")}
  end

  @impl true
  def handle_event(
        "create_random_custom_alias",
        _params,
        %{assigns: %{custom_alias_domain: nil}} = socket
      ) do
    {:noreply, push_event(socket, "custom-alias-error", %{})}
  end

  def handle_event("create_random_custom_alias", _params, socket) do
    domain = String.trim_leading(socket.assigns.custom_alias_domain, "@")
    name = Aliases.generate_alias_name(domain)

    handle_event("create_custom_alias", %{"alias_name" => name}, socket)
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
          socket =
            socket
            |> put_notification(:success, "Created new alias #{email_alias.address}.")

          {:noreply,
           push_navigate(socket,
             to: ~p"/alias/#{email_alias.address}"
           )}

        {:error, %Ecto.Changeset{} = changeset} ->
          {error, _} = Keyword.get(changeset.errors, :address)

          socket =
            socket
            |> assign(:custom_alias_error, error)
            |> put_notification(:error, "Something went wrong.")
            |> push_event("custom-alias-error", %{})

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_notification(:error, "Something went wrong.")
           |> push_event("custom-alias-error", %{})}
      end
    else
      {:noreply,
       socket
       |> put_notification(:error, "You don't have permission to do that.")
       |> push_event("custom-alias-error", %{})}
    end
  end

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: aliases_path(1, query), replace: true)}
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
            |> put_notification(:info, "#{verb} #{email_alias.address}.")

          {:error, _error} ->
            socket
            |> put_notification(:error, "Something went wrong.")
        end
      else
        socket |> put_notification(:error, "You don't have permission to do that.")
      end

    {:noreply, socket}
  end

  defp aliases_path(page_number, ""), do: ~p"/?#{[page: page_number]}"

  defp aliases_path(page_number, query), do: ~p"/?#{[page: page_number, query: query]}"

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp pagination_pages(_page, total) when total <= 7, do: Enum.to_list(1..total)

  defp pagination_pages(page, total) do
    [1, page - 1, page, page + 1, total]
    |> Enum.filter(&(&1 >= 1 and &1 <= total))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce([], fn number, acc ->
      case acc do
        [previous | _] when number - previous > 1 -> [number, :ellipsis | acc]
        _ -> [number | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp assign_at_free_limit(socket) do
    user = socket.assigns.current_user
    at_limit = user.status == :free and socket.assigns.alias_count >= Aliases.free_alias_limit()
    assign(socket, :at_free_limit, at_limit)
  end

  defp update_custom_domains(socket) do
    domains =
      socket.assigns[:current_user]
      |> Domain.list_custom_domains()

    assign(
      socket,
      :custom_domains,
      domains
    )
  end

  attr(:at_free_limit, :boolean, required: true)
  attr(:custom_domains, :list, required: true)

  defp new_alias_button(assigns) do
    ~H"""
    <%= if @at_free_limit do %>
      <div x-init x-tooltip.raw="Upgrade to create more aliases">
        <.button text="New alias" icon={:plus} disabled={true} />
      </div>
    <% else %>
      <%= if Enum.empty?(@custom_domains) do %>
        <.button click="add_alias" text="New alias" icon={:plus} />
      <% else %>
        <.button_with_dropdown click="add_alias" text="New alias" icon={:plus}>
          <.dropdown_item
            id="new-alias-default-domain"
            index={0}
            click="add_alias"
            text={"@#{Util.email_domain()}"}
          />
          <%= for {domain, index} <- Enum.with_index(@custom_domains, 1) do %>
            <% verified = Domain.fully_verified?(domain) %>
            <.dropdown_item
              id={"new-alias-domain-#{domain.id}"}
              index={index}
              click="open_custom_alias_modal"
              text={"@#{domain.domain}"}
              disabled={!verified}
              tooltip={if(!verified, do: "Domain is not verified")}
            />
          <% end %>
        </.button_with_dropdown>
      <% end %>
    <% end %>
    """
  end
end
