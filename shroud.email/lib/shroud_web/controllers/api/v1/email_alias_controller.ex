defmodule ShroudWeb.Api.V1.EmailAliasController do
  use ShroudWeb, :controller
  import Ecto.Query
  alias Shroud.Repo
  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Domain.CustomDomain

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

  def show(conn, %{"address" => address}) do
    case find_alias(conn, address) do
      nil -> render_error(conn, 404, "Alias not found")
      email_alias -> render(conn, "email_alias.json", data: email_alias)
    end
  end

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

  def create(conn, %{"local_part" => local_part, "domain" => domain} = params) do
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

  def create(conn, params) do
    conn.assigns.current_user
    |> Aliases.create_random_email_alias(alias_metadata(params))
    |> render_alias_result(conn)
  end

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
