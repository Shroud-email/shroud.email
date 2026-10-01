defmodule ShroudWeb.Api.V1.TokenController do
  use ShroudWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Shroud.Accounts
  alias ShroudWeb.Api.V1.Schemas
  alias ShroudWeb.Plugs.RateLimit

  operation(:create,
    operation_id: "createToken",
    tags: ["Authentication"],
    summary: "Create an API token",
    description: """
    Creates an API token for your account. Keep the returned token secret.
    """,
    security: [],
    request_body: {"Credentials", "application/json", Schemas.token_request(), required: true},
    responses: [
      ok: {"API token", "application/json", Schemas.token()},
      forbidden:
        {"Invalid email, password or TOTP code", "application/json", Schemas.error(),
         example: %{error: "Invalid email, password or TOTP code"}}
    ]
  )

  def create(conn, %{"email" => email, "password" => password} = params) do
    user = Accounts.get_user_by_email_and_password(email, password)

    conn =
      if user && user.totp_enabled do
        conn
        |> RateLimit.enforce(:second_factor, {:ip, conn.remote_ip})
        |> RateLimit.enforce(:second_factor, {:account, user.id})
      else
        conn
      end

    cond do
      conn.halted ->
        conn

      user && valid_totp?(user, params["totp"]) ->
        token = Accounts.generate_user_session_token(user)
        render(conn, "token.json", token: Base.encode64(token))

      true ->
        conn
        |> put_status(403)
        |> put_view(ShroudWeb.ErrorJSON)
        |> render("error.json", error: "Invalid email, password or TOTP code")
    end
  end

  defp valid_totp?(%{totp_enabled: false}, _totp), do: true

  defp valid_totp?(user, totp) do
    totp =
      if is_nil(totp), do: "", else: totp |> Integer.to_string() |> String.pad_leading(6, "0")

    Accounts.TOTP.valid_code?(user, user.totp_secret, totp)
  end
end
