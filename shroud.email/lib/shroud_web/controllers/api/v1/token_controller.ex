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
    case get_user(conn, email, password, params["totp"]) do
      {:rate_limited, conn} ->
        conn

      %Accounts.User{} = user ->
        token = Accounts.generate_user_session_token(user)
        render(conn, "token.json", token: Base.encode64(token))

      nil ->
        conn
        |> put_status(403)
        |> put_view(ShroudWeb.ErrorJSON)
        |> render("error.json", error: "Invalid email, password or TOTP code")
    end
  end

  defp get_user(conn, email, password, totp) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      if user.totp_enabled do
        conn =
          conn
          |> RateLimit.enforce(:second_factor, {:ip, conn.remote_ip})
          |> RateLimit.enforce(:second_factor, {:account, user.id})

        totp =
          if is_nil(totp) || conn.halted,
            do: "",
            else: totp |> Integer.to_string() |> String.pad_leading(6, "0")

        with %{halted: false} <- conn,
             true <- Accounts.TOTP.valid_code?(user, user.totp_secret, totp) do
          user
        else
          false -> nil
          conn -> {:rate_limited, conn}
        end
      else
        user
      end
    else
      nil
    end
  end
end
