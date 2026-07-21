defmodule ShroudWeb.Plugs.VerifyCaptcha do
  @moduledoc """
  Verifies the Cap CAPTCHA token on protected form submissions.

  This plug is a **no-op when Cap is disabled** (any of the three CAP_*
  env vars unset), which is what makes Cap optional for self-hosters.

  When enabled, it reads `cap-token` from the request params and verifies
  it via `Shroud.Captcha.verify/1` before the controller action runs.
  On failure it flashes an error and redirects back to the form.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller

  alias Shroud.Captcha

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Captcha.enabled?() do
      verify_token(conn, conn.params["cap-token"])
    else
      conn
    end
  end

  defp verify_token(conn, token) do
    case Captcha.verify(token) do
      :ok ->
        conn

      {:error, _reason} ->
        conn
        |> put_flash(:error, "CAPTCHA verification failed. Please try again.")
        |> redirect(to: form_route(conn))
        |> halt()
    end
  end

  # Redirect back to the form that was being submitted. We key off the
  # request path so each protected route returns to its own form.
  defp form_route(%Plug.Conn{request_path: "/users/log_in"}), do: "/users/log_in"
  defp form_route(%Plug.Conn{request_path: "/users/reset_password"}), do: "/users/reset_password"
  defp form_route(_conn), do: "/users/register"
end
