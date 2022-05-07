defmodule ShroudWeb.Api.V1.EmailAliasController do
  use ShroudWeb, :controller
  import Ecto.Query
  alias Shroud.Repo
  alias Shroud.Aliases.EmailAlias

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
end
