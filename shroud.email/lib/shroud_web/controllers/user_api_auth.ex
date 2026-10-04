defmodule ShroudWeb.UserApiAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Shroud.{Accounts, Mcp}

  def fetch_current_api_user(conn, _opts) do
    {user_token, conn} = ensure_api_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)

    if user do
      assign(conn, :current_user, user)
    else
      token = bearer_token(conn)

      case Mcp.with_access(token, Mcp.api_resource(), nil, fn connection ->
             {:ok, connection.user}
           end) do
        {:ok, user} -> conn |> assign(:current_user, user) |> assign(:oauth_token, token)
        _ -> assign(conn, :current_user, nil)
      end
    end
  end

  def require_api_scope(conn, scope) do
    if token = conn.assigns[:oauth_token] do
      case Mcp.with_access(token, Mcp.api_resource(), scope, fn _ -> :ok end) do
        :ok -> conn
        {:error, :insufficient_scope} -> oauth_error(conn, 403, "insufficient_scope", scope)
        _ -> oauth_error(conn, 401, "invalid_token", scope)
      end
    else
      conn
    end
  end

  defp oauth_error(conn, status, error, scope) do
    scopes = if scope, do: ~s(, scope="#{Enum.join(Mcp.required_scopes(scope), " ")}"), else: ""

    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer resource_metadata="#{Mcp.issuer()}/.well-known/oauth-protected-resource/api/v1", error="#{error}") <>
        scopes
    )
    |> put_resp_header("cache-control", "no-store")
    |> put_view(ShroudWeb.ErrorJSON)
    |> put_status(status)
    |> render("error.json", %{
      error: if(error == "invalid_token", do: "Invalid token", else: error)
    })
    |> halt()
  end

  def require_confirmed_api_user(conn, _opts) do
    user = conn.assigns[:current_user]

    case user do
      nil ->
        oauth_error(conn, 401, "invalid_token", nil)

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

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [authorization] ->
        case Regex.run(~r/\ABearer +([A-Za-z0-9._~+\/-]+=*)\z/i, authorization,
               capture: :all_but_first
             ) do
          [token] when byte_size(token) in 1..1024 -> token
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp ensure_api_token(conn) do
    case bearer_token(conn) do
      token when is_binary(token) ->
        case Base.decode64(token) do
          {:ok, decoded_token} -> {decoded_token, conn}
          :error -> {nil, conn}
        end

      nil ->
        {nil, conn}
    end
  end
end
