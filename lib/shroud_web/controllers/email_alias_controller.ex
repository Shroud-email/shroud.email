defmodule ShroudWeb.EmailAliasController do
  use ShroudWeb, :controller

  alias Shroud.Shroudes

  def index(conn, _params) do
    aliases = Shroudes.list_aliases!(conn.assigns[:current_user])
    render(conn, "index.html", aliases: aliases)
  end

  # def new(conn, _params) do
  #   changeset = Shroudes.EmailAlias.changeset(%Shroudes.EmailAlias{})
  #   render(conn, "new.html", changeset: changeset)
  # end

  def create(conn, _params) do
    case Shroudes.create_random_email_alias(conn.assigns[:current_user]) do
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
    case Shroudes.delete_email_alias(id) do
      {:ok, _struct} -> conn |> put_flash(:info, "Deleted address.") |> redirect(to: "/addresses")
      {:error, _struct} -> conn |> put_flash(:error, "Something went wrong") |> redirect(to: "/addresses")
    end
  end

end
