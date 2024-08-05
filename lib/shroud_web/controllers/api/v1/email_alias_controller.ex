defmodule ShroudWeb.Api.V1.EmailAliasController do
  use ShroudWeb, :controller
  import Ecto.Query
  alias Shroud.Repo
  alias Shroud.Aliases
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Domain.CustomDomain

  def index(conn, params) do
    page =
      EmailAlias
      |> where([ea], is_nil(ea.deleted_at))
      |> where([ea], ea.user_id == ^conn.assigns.current_user.id)
      |> order_by(desc: :inserted_at)
      |> Repo.paginate(params)

    render(conn, "index.json",
      email_aliases: page.entries,
      page_number: page.page_number,
      page_size: page.page_size,
      total_pages: page.total_pages,
      total_entries: page.total_entries
    )
  end

  def create(conn, %{"local_part" => local_part, "domain" => domain}) do
    domain = Repo.get_by(CustomDomain, domain: domain, user_id: conn.assigns.current_user.id)

    if is_nil(domain) do
      conn
      |> put_status(422)
      |> put_view(ShroudWeb.ErrorView)
      |> render("error.json", error: "Domain not found")
    else
      params = %{address: "#{local_part}@#{domain.domain}", user_id: conn.assigns.current_user.id}

      case Aliases.create_email_alias(params) do
        {:ok, email_alias} ->
          render(conn, "email_alias.json", data: email_alias)

        {:error, changeset} ->
          {error, _} = Keyword.get(changeset.errors, :address)

          conn
          |> put_status(422)
          |> put_view(ShroudWeb.ErrorView)
          |> render("error.json", error: error)
      end
    end
  end

  def create(conn, _params) do
    case Aliases.create_random_email_alias(conn.assigns.current_user) do
      {:ok, email_alias} ->
        render(conn, "email_alias.json", data: email_alias)

      _ ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShroudWeb.ErrorView)
        |> render("error.json", error: "Unable to create email alias")
    end
  end

  def delete(conn, %{"address" => address}) do
    alias =
      EmailAlias
      |> where([ea], is_nil(ea.deleted_at))
      |> where([ea], ea.user_id == ^conn.assigns.current_user.id)
      |> Repo.get_by(address: address)

    if is_nil(alias) do
      conn
      |> put_status(422)
      |> put_view(ShroudWeb.ErrorView)
      |> render("error.json", error: "Alias not found")
    else
      Aliases.delete_email_alias(alias.id)

      conn
      |> send_resp(:no_content, "")
    end
  end
end
