defmodule ShroudWeb.Plugs.OAuthCors do
  import Plug.Conn
  alias Shroud.OAuth

  def init(opts), do: opts

  def call(%{path_info: path} = conn, _opts)
      when path in [
             ["oauth", "register"],
             ["oauth", "token"],
             ["oauth", "revoke"],
             [".well-known", "oauth-authorization-server"],
             [".well-known", "oauth-protected-resource"],
             [".well-known", "oauth-protected-resource", "mcp"],
             [".well-known", "oauth-protected-resource", "api", "v1"]
           ] do
    with true <- conn.host == URI.parse(OAuth.issuer()).host,
         [origin] <- get_req_header(conn, "origin") do
      conn = put_headers(conn, origin)

      if conn.method == "OPTIONS" do
        conn
        |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "Content-Type, Accept")
        |> send_resp(204, "")
        |> halt()
      else
        conn
      end
    else
      _ -> conn
    end
  end

  def call(%{path_info: ["api", "v1" | _]} = conn, _opts) do
    with true <- conn.host == URI.parse(OAuth.issuer()).host,
         [origin] <- get_req_header(conn, "origin") do
      conn = put_headers(conn, origin)

      if conn.method == "OPTIONS" do
        conn
        |> put_resp_header("access-control-allow-methods", "GET, POST, PATCH, DELETE, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "Authorization, Content-Type, Accept")
        |> send_resp(204, "")
        |> halt()
      else
        conn
      end
    else
      _ -> conn
    end
  end

  def call(%{path_info: [resource | _]} = conn, _opts) do
    with true <- URI.decode(resource) == "mcp",
         true <- conn.host == URI.parse(OAuth.issuer()).host,
         [origin] <- get_req_header(conn, "origin") do
      put_headers(conn, origin)
    else
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  def put_headers(conn, origin) do
    conn
    |> put_resp_header("vary", "Origin")
    |> put_resp_header("access-control-allow-origin", origin)
    |> put_resp_header(
      "access-control-expose-headers",
      "WWW-Authenticate, MCP-Session-Id, MCP-Protocol-Version, Retry-After"
    )
  end
end
