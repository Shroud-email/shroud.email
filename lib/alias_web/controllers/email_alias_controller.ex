defmodule AliasWeb.EmailAliasController do
  use AliasWeb, :controller

  alias Alias.Aliases

  def index(conn, _params) do
    aliases = Aliases.list_aliases!(conn.assigns[:current_user])
    render(conn, "index.html", aliases: aliases)
  end

  # def new(conn, _params) do
  #   changeset = Aliases.EmailAlias.changeset(%Aliases.EmailAlias{})
  #   render(conn, "new.html", changeset: changeset)
  # end

  def create(conn, _params) do
    case Aliases.create_random_email_alias(conn.assigns[:current_user]) do
      {:ok, _struct} ->
        conn
        |> put_flash(:info, "Created new address.")
        |> redirect(to: Routes.email_alias_path(conn, :index))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Something went wrong.")
        |> redirect(to: Routes.email_alias_path(conn, :index))
    end
  end

  def delete(conn, %{"id" => id}) do
    case Aliases.delete_email_alias(id) do
      {:ok, _struct} -> conn |> put_flash(:info, "Deleted address.") |> redirect(to: "/addresses")
      {:error, _struct} -> conn |> put_flash(:error, "Something went wrong") |> redirect(to: "/addresses")
    end
  end

end
