defmodule ShroudWeb.UserApiAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Shroud.Accounts

  def fetch_current_api_user(conn, _opts) do
    {user_token, conn} = ensure_api_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  def require_confirmed_api_user(conn, _opts) do
    user = conn.assigns[:current_user]

    case user do
      nil ->
        conn
        |> put_view(ShroudWeb.ErrorJSON)
        |> put_status(403)
        |> render("error.json", %{error: "Invalid token"})
        |> halt()

      %{confirmed_at: nil} ->
        conn
        |> put_view(ShroudWeb.ErrorJSON)
        |> put_status(403)
        |> render("error.json", %{error: "Please confirm your account"})
        |> halt()

      _user ->
        conn
    end
  end

  defp ensure_api_token(conn) do
    case get_req_header(conn, "authorization") do
      [header_value] ->
        case Regex.named_captures(~r/Bearer (?<token>[^\s]+)/i, header_value) do
          %{"token" => token} ->
            # A malformed (non-base64) token is treated like a missing token
            # rather than raising a MatchError (which would surface as a 500).
            case Base.decode64(token) do
              {:ok, decoded_token} -> {decoded_token, conn}
              :error -> {nil, conn}
            end

          _ ->
            {nil, conn}
        end

      _ ->
        {nil, conn}
    end
  end
end
