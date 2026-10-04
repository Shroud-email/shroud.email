defmodule ShroudWeb.Api.V1.ProfileController do
  use ShroudWeb, :controller
  use OpenApiSpex.ControllerSpecs
  import ShroudWeb.UserApiAuth, only: [require_api_scope: 2]
  alias OpenApiSpex.Schema
  alias ShroudWeb.Api.V1.Schemas

  plug :require_api_scope, "profile:read"

  operation(:show,
    operation_id: "getProfile",
    tags: ["Account"],
    summary: "Get the authenticated account identity",
    description: "OAuth clients need the profile:read scope. Returns only the email address.",
    responses: [
      ok:
        {"Account identity", "application/json",
         %Schema{
           title: "Profile",
           type: :object,
           required: [:email],
           properties: %{
             email: %Schema{type: :string, format: :email}
           },
           example: %{email: "user@example.com"}
         }},
      unauthorized: {"Invalid token", "application/json", Schemas.error()},
      forbidden:
        {"Insufficient scope or unconfirmed account", "application/json", Schemas.error()}
    ]
  )

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{
      email: conn.assigns.current_user.email
    })
  end
end
