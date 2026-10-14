defmodule ShroudWeb.Api.V1.AliasCapabilitiesController do
  use ShroudWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Shroud.Aliases
  alias ShroudWeb.Api.V1.Schemas
  import ShroudWeb.UserApiAuth, only: [require_api_scope: 2]

  plug :require_api_scope, "aliases:read"

  operation(:show,
    operation_id: "getAliasCapabilities",
    tags: ["Aliases"],
    summary: "Get alias creation capacity and default domain",
    description:
      "Non-deleted aliases count toward capacity, including disabled aliases. OAuth scope: aliases:read.",
    responses: [
      ok: {"Alias capabilities", "application/json", Schemas.alias_capabilities()},
      unauthorized: {"Invalid token", "application/json", Schemas.error()},
      forbidden:
        {"Insufficient scope or unconfirmed account", "application/json", Schemas.error()}
    ]
  )

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(Aliases.creation_capabilities(conn.assigns.current_user))
  end
end
