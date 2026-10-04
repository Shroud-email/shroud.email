defmodule ShroudWeb.Plugs.McpAuth do
  import Plug.Conn
  import ShroudWeb.Plugs.OAuthCors, only: [put_headers: 2]
  alias Shroud.OAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.host == URI.parse(OAuth.issuer()).host,
      do: authenticate_request(conn),
      else: conn |> send_resp(403, "Forbidden host") |> halt()
  end

  defp authenticate_request(conn) do
    token =
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

    case get_req_header(conn, "origin") do
      [] ->
        authenticate(conn, token)

      [origin] ->
        conn |> put_headers(origin) |> authenticate_or_preflight(token)

      _ ->
        conn |> send_resp(403, "Forbidden origin") |> halt()
    end
  end

  defp authenticate_or_preflight(%{method: "OPTIONS"} = conn, _token) do
    conn
    |> put_resp_header("access-control-allow-methods", "POST, DELETE, OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "Authorization, Content-Type, Accept, MCP-Protocol-Version, MCP-Session-Id, MCP-Method, MCP-Name, Last-Event-ID"
    )
    |> send_resp(204, "")
    |> halt()
  end

  defp authenticate_or_preflight(conn, token), do: authenticate(conn, token)

  def handler_opts(conn, _request), do: [token: conn.assigns.mcp_token]

  def challenge(reason \\ :invalid_token, scope \\ nil) do
    error = if reason == :insufficient_scope, do: "insufficient_scope", else: "invalid_token"
    scope = if scope, do: Enum.join(OAuth.required_scopes(scope), " ")
    scope_part = if scope, do: ", scope=\"#{scope}\"", else: ""

    ~s(Bearer resource_metadata="#{OAuth.issuer()}/.well-known/oauth-protected-resource", error="#{error}", error_description="Connect your Shroud.email account") <>
      scope_part
  end

  defp authenticate(conn, token) do
    case OAuth.with_access(token, OAuth.resource(:mcp), nil, fn connection ->
           {:ok, connection.user_id}
         end) do
      {:ok, user_id} ->
        conn = ShroudWeb.Plugs.RateLimit.enforce(conn, :api, {:account, user_id})

        cond do
          conn.halted ->
            conn

          conn.method == "GET" and conn.request_path == "/mcp" ->
            conn
            |> put_resp_header("allow", "POST, DELETE")
            |> send_resp(405, "Streaming not supported")
            |> halt()

          true ->
            assign(conn, :mcp_token, token)
        end

      _ ->
        conn
        |> put_resp_header("www-authenticate", challenge())
        |> put_resp_content_type("application/json")
        |> send_resp(
          401,
          Jason.encode!(%{
            error_code: "AUTHENTICATION_REQUIRED",
            error: "Authentication required"
          })
        )
        |> halt()
    end
  end
end
