defmodule ShroudWeb.Api.V1.DomainController do
  use ShroudWeb, :controller
  use OpenApiSpex.ControllerSpecs
  import Ecto.Query
  alias Shroud.Domain.CustomDomain
  alias Shroud.Repo
  alias ShroudWeb.Api.V1.Schemas

  operation(:index,
    operation_id: "listDomains",
    tags: ["Domains"],
    summary: "List custom domains",
    description: """
    Lists your custom domains with valid DNS records (all verification checks within
    the last day).
    """,
    parameters: Schemas.pagination_parameters(),
    responses: [
      ok: {"Custom domains", "application/json", Schemas.domains_page()},
      forbidden: {"Invalid token or unconfirmed account", "application/json", Schemas.error()}
    ]
  )

  def index(conn, params) do
    one_day_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-1 * 60 * 60 * 24)

    page =
      CustomDomain
      |> where([ea], ea.user_id == ^conn.assigns.current_user.id)
      |> where([ea], ea.ownership_verified_at >= ^one_day_ago)
      |> where([ea], ea.spf_verified_at >= ^one_day_ago)
      |> where([ea], ea.mx_verified_at >= ^one_day_ago)
      |> where([ea], ea.dmarc_verified_at >= ^one_day_ago)
      |> where([ea], ea.dkim_verified_at >= ^one_day_ago)
      |> order_by(desc: :inserted_at)
      |> Repo.paginate(params)

    render(conn, "index.json",
      domains: page.entries,
      page_number: page.page_number,
      page_size: page.page_size,
      total_pages: page.total_pages,
      total_entries: page.total_entries
    )
  end
end
