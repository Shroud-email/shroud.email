defmodule ShroudWeb.Api.V1.EmailAliasController do
  use ShroudWeb, :controller
  use OpenApiSpex.ControllerSpecs
  import Ecto.Query
  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Domain.CustomDomain
  alias Shroud.Repo
  alias ShroudWeb.Api.V1.Schemas

  tags(["Aliases"])

  operation(:index,
    operation_id: "listAliases",
    summary: "List email aliases",
    description: "Lists your non-deleted email aliases, newest first.",
    parameters:
      Schemas.pagination_parameters() ++
        [
          search: [
            in: :query,
            type: :string,
            description:
              "Case-insensitive search across address, title and notes. Space-separated terms match any term; punctuation acts as a wildcard.",
            example: "Acme"
          ],
          enabled: [
            in: :query,
            type: :boolean,
            description: "Filter enabled or disabled aliases.",
            example: false
          ]
        ],
    responses: [
      ok: {"Email aliases", "application/json", Schemas.aliases_page()},
      forbidden: {"Invalid token or unconfirmed account", "application/json", Schemas.error()},
      unprocessable_entity:
        {"Invalid search or enabled filter", "application/json", Schemas.error(),
         example: %{error: "Invalid search or enabled filter"}}
    ]
  )

  def index(conn, params) do
    filters =
      {%{}, %{search: :string, enabled: :boolean}}
      |> Ecto.Changeset.cast(params, [:search, :enabled])
      |> Ecto.Changeset.apply_action(:index)

    case filters do
      {:ok, filters} ->
        query = Aliases.aliases_query(conn.assigns.current_user, filters[:search])

        query =
          if is_boolean(filters[:enabled]) do
            where(query, [ea], ea.enabled == ^filters.enabled)
          else
            query
          end

        page = Repo.paginate(query, params)

        render(conn, "index.json",
          email_aliases: page.entries,
          page_number: page.page_number,
          page_size: page.page_size,
          total_pages: page.total_pages,
          total_entries: page.total_entries
        )

      {:error, _changeset} ->
        render_error(conn, 422, "Invalid search or enabled filter")
    end
  end

  operation(:show,
    operation_id: "getAlias",
    summary: "Get an alias",
    description: "Fetches a single alias.",
    parameters: Schemas.address_parameter(),
    responses: [
      ok: {"Email alias", "application/json", Schemas.email_alias()},
      forbidden: {"Invalid token or unconfirmed account", "application/json", Schemas.error()},
      not_found:
        {"Alias not found", "application/json", Schemas.error(),
         example: %{error: "Alias not found"}}
    ]
  )

  def show(conn, %{"address" => address}) do
    case find_alias(conn, address) do
      nil -> render_error(conn, 404, "Alias not found")
      email_alias -> render(conn, "email_alias.json", data: email_alias)
    end
  end

  operation(:update,
    operation_id: "updateAlias",
    summary: "Update an alias",
    description: "Updates an alias's settings.",
    parameters: Schemas.address_parameter(),
    request_body:
      {"Fields to update", "application/json", Schemas.update_alias(), required: false},
    responses: [
      ok: {"Updated alias", "application/json", Schemas.email_alias()},
      forbidden: {"Invalid token or unconfirmed account", "application/json", Schemas.error()},
      not_found:
        {"Alias not found", "application/json", Schemas.error(),
         example: %{error: "Alias not found"}},
      unprocessable_entity:
        {"Invalid values", "application/json", Schemas.error(), example: %{error: "is invalid"}}
    ]
  )

  def update(conn, %{"address" => address} = params) do
    case find_alias(conn, address) do
      nil ->
        render_error(conn, 404, "Alias not found")

      email_alias ->
        email_alias
        |> Aliases.update_email_alias(Map.take(params, ["title", "notes", "enabled"]))
        |> render_alias_result(conn)
    end
  end

  operation(:create,
    operation_id: "createAlias",
    summary: "Create an alias",
    description: """
    Creates an enabled alias with a random or custom address. Random addresses use
    the default shared domain (`@fog.shroud.email` on hosted Shroud.email).
    """,
    request_body:
      {"Optional alias settings", "application/json", Schemas.create_alias(), required: false},
    responses: [
      ok:
        {"Created alias", "application/json", Schemas.email_alias(),
         example: %{
           address: "myemail@example.com",
           blocked: 0,
           forwarded: 0,
           title: "Acme",
           notes: "Used for shopping receipts",
           blocked_addresses: [],
           enabled: true
         }},
      forbidden:
        {"Invalid token, unconfirmed/inactive account, or free plan alias limit reached",
         "application/json", Schemas.error()},
      unprocessable_entity:
        {"Invalid metadata, address, or domain", "application/json", Schemas.error(),
         example: %{error: "Domain not found"}}
    ]
  )

  def create(conn, %{"local_part" => local_part, "domain" => domain} = params)
      when is_binary(local_part) and is_binary(domain) do
    domain = Repo.get_by(CustomDomain, domain: domain, user_id: conn.assigns.current_user.id)

    if is_nil(domain) do
      render_error(conn, 422, "Domain not found")
    else
      params
      |> alias_metadata()
      |> Map.merge(%{
        address: "#{local_part}@#{domain.domain}",
        user_id: conn.assigns.current_user.id
      })
      |> Aliases.create_email_alias()
      |> render_alias_result(conn)
    end
  end

  def create(conn, params)
      when is_map_key(params, "local_part") or is_map_key(params, "domain") do
    render_error(conn, 422, "local_part and domain must both be strings")
  end

  def create(conn, params) do
    conn.assigns.current_user
    |> Aliases.create_random_email_alias(alias_metadata(params))
    |> render_alias_result(conn)
  end

  operation(:delete,
    operation_id: "deleteAlias",
    summary: "Delete an alias",
    description: """
    Deletes an alias from your account.
    Prefer disabling an alias if you may need it again. Deleted aliases on shared
    Shroud domains cannot be recreated; custom-domain addresses can be recreated.
    """,
    parameters: Schemas.address_parameter(),
    responses: [
      no_content: "Alias deleted",
      forbidden: {"Invalid token or unconfirmed account", "application/json", Schemas.error()},
      unprocessable_entity:
        {"Alias not found", "application/json", Schemas.error(),
         example: %{error: "Alias not found"}}
    ]
  )

  def delete(conn, %{"address" => address}) do
    alias = find_alias(conn, address)

    if is_nil(alias) do
      render_error(conn, 422, "Alias not found")
    else
      Aliases.delete_email_alias(alias.id)

      conn
      |> send_resp(:no_content, "")
    end
  end

  defp find_alias(conn, address) do
    EmailAlias
    |> where([ea], is_nil(ea.deleted_at))
    |> where([ea], ea.user_id == ^conn.assigns.current_user.id)
    |> Repo.get_by(address: address)
  end

  defp alias_metadata(params) do
    params
    |> Map.take(["title", "notes"])
    |> Enum.into(%{}, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp render_alias_result({:ok, email_alias}, conn) do
    render(conn, "email_alias.json", data: email_alias)
  end

  defp render_alias_result({:error, :free_limit_reached}, conn) do
    render_error(conn, 403, "Free plan alias limit reached. Upgrade to create more aliases.")
  end

  defp render_alias_result({:error, :inactive_user}, conn) do
    render_error(conn, 403, "Account is inactive")
  end

  defp render_alias_result({:error, %Ecto.Changeset{} = changeset}, conn) do
    error =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
        Enum.reduce(opts, message, fn {key, value}, message ->
          String.replace(message, "%{#{key}}", to_string(value))
        end)
      end)
      |> Map.values()
      |> List.flatten()
      |> Enum.join(", ")

    render_error(conn, 422, error)
  end

  defp render_error(conn, status, error) do
    conn
    |> put_status(status)
    |> put_view(ShroudWeb.ErrorJSON)
    |> render("error.json", error: error)
  end
end
