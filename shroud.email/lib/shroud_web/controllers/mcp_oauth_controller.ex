defmodule ShroudWeb.McpOAuthController do
  use ShroudWeb, :controller
  alias Shroud.Mcp

  plug :put_private_headers

  def metadata(conn, _params) do
    json(conn, %{
      issuer: Mcp.issuer(),
      authorization_endpoint: Mcp.issuer() <> "/oauth/authorize",
      token_endpoint: Mcp.issuer() <> "/oauth/token",
      revocation_endpoint: Mcp.issuer() <> "/oauth/revoke",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      token_endpoint_auth_methods_supported: ["none"],
      revocation_endpoint_auth_methods_supported: ["none"],
      code_challenge_methods_supported: ["S256"],
      authorization_response_iss_parameter_supported: true,
      scopes_supported: Map.keys(Mcp.permissions())
    })
  end

  def resource_metadata(conn, _params) do
    json(conn, %{
      resource: Mcp.resource(),
      authorization_servers: [Mcp.issuer()],
      scopes_supported: Map.keys(Mcp.permissions()),
      bearer_methods_supported: ["header"]
    })
  end

  def authorize(conn, params) do
    case Mcp.validate_authorization(params) do
      {:ok, details} ->
        approval =
          Phoenix.Token.sign(
            ShroudWeb.Endpoint,
            "mcp-consent",
            {conn.assigns.current_user.id, params}
          )

        conn
        |> put_root_layout(html: {ShroudWeb.Layouts, :connection})
        |> render(:consent, details: details, approval: approval, page_title: "Connect account")

      {:error, _} ->
        invalid(conn)
    end
  end

  def consent(conn, %{"approval" => approval, "decision" => decision}) do
    with {:ok, {user_id, params}} <-
           Phoenix.Token.verify(ShroudWeb.Endpoint, "mcp-consent", approval, max_age: 600),
         true <- user_id == conn.assigns.current_user.id,
         {:ok, _} <- Mcp.validate_authorization(params) do
      case decision do
        "allow" ->
          case Mcp.authorize(conn.assigns.current_user, params) do
            {:ok, code} -> callback(conn, params, %{code: code})
            _ -> invalid(conn)
          end

        "deny" ->
          callback(conn, params, %{error: "access_denied"})

        _ ->
          invalid(conn)
      end
    else
      _ -> invalid(conn)
    end
  end

  def consent(conn, _params), do: invalid(conn)

  def token(conn, _params) do
    # OAuth credentials belong in the POST body, never the URL or browser session.
    case Mcp.exchange(conn.body_params) do
      {:ok, tokens} -> json(conn, tokens)
      {:error, :invalid_request} -> conn |> put_status(400) |> json(%{error: "invalid_request"})
      {:error, _} -> conn |> put_status(400) |> json(%{error: "invalid_grant"})
    end
  end

  def revoke(conn, _params) do
    Mcp.revoke_token(conn.body_params["token"], conn.body_params["client_id"])
    send_resp(conn, 200, "")
  end

  defp callback(conn, params, result) do
    uri = URI.parse(params["redirect_uri"])

    query =
      URI.decode_query(uri.query || "")
      |> Map.merge(Map.new(result, fn {key, value} -> {Atom.to_string(key), value} end))

    query = Map.merge(query, %{"state" => params["state"], "iss" => Mcp.issuer()})
    redirect(conn, external: URI.to_string(%{uri | query: URI.encode_query(query)}))
  end

  defp invalid(conn),
    do:
      conn
      |> put_status(400)
      |> text("Invalid or expired connection request. Start again from your MCP client.")

  defp put_private_headers(conn, _opts),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
end
