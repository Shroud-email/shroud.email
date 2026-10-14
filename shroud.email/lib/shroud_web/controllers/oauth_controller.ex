defmodule ShroudWeb.OAuthController do
  use ShroudWeb, :controller
  alias Shroud.OAuth

  plug :put_root_layout, html: {ShroudWeb.Layouts, :connection}
  plug :put_private_headers
  plug ShroudWeb.Plugs.RateLimit, :routes when action in [:register, :token, :revoke]
  plug :require_resource_enabled when action in [:authorize, :consent]

  defp require_resource_enabled(conn, _opts) do
    params = conn.params

    target =
      case params do
        %{"approval" => approval} ->
          case Phoenix.Token.verify(ShroudWeb.Endpoint, "mcp-consent", approval, max_age: 600) do
            {:ok, {_id, request}} -> request["resource"]
            _ -> nil
          end

        _ ->
          params["resource"]
      end

    if OAuth.enabled?(conn.assigns.current_user, target || OAuth.resource(:mcp)),
      do: conn,
      else: conn |> send_resp(404, "Not found") |> halt()
  end

  def register(conn, _params) do
    case OAuth.Clients.register(conn.body_params) do
      {:ok, client} -> conn |> put_status(201) |> json(client)
      {:error, error} -> conn |> put_status(400) |> json(%{error: error})
    end
  end

  def metadata(conn, _params) do
    json(conn, %{
      issuer: OAuth.issuer(),
      authorization_endpoint: OAuth.issuer() <> "/oauth/authorize",
      token_endpoint: OAuth.issuer() <> "/oauth/token",
      registration_endpoint: OAuth.issuer() <> "/oauth/register",
      revocation_endpoint: OAuth.issuer() <> "/oauth/revoke",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      token_endpoint_auth_methods_supported: ["none"],
      revocation_endpoint_auth_methods_supported: ["none"],
      code_challenge_methods_supported: ["S256"],
      authorization_response_iss_parameter_supported: true,
      scopes_supported: Map.keys(OAuth.permissions(OAuth.resource(:api)))
    })
  end

  def resource_metadata(conn, _params) do
    target =
      if conn.request_path == "/.well-known/oauth-protected-resource/api/v1",
        do: OAuth.resource(:api),
        else: OAuth.resource(:mcp)

    json(conn, %{
      resource: target,
      authorization_servers: [OAuth.issuer()],
      scopes_supported: Map.keys(OAuth.permissions(target)),
      bearer_methods_supported: ["header"]
    })
  end

  def authorize(conn, params) do
    case OAuth.validate_authorization(params) do
      {:ok, details} ->
        approval =
          Phoenix.Token.sign(
            ShroudWeb.Endpoint,
            "mcp-consent",
            {conn.assigns.current_user.id, params}
          )

        conn
        |> render(:consent, details: details, approval: approval, page_title: "Connect account")

      {:error, _} ->
        invalid(conn)
    end
  end

  def consent(conn, %{"approval" => approval, "decision" => decision}) do
    with {:ok, {user_id, params}} <-
           Phoenix.Token.verify(ShroudWeb.Endpoint, "mcp-consent", approval, max_age: 600),
         true <- user_id == conn.assigns.current_user.id,
         {:ok, _} <- OAuth.validate_authorization(params) do
      case decision do
        "allow" ->
          case OAuth.authorize(conn.assigns.current_user, params) do
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
    case OAuth.exchange(conn.body_params) do
      {:ok, tokens} -> json(conn, tokens)
      {:error, :invalid_request} -> conn |> put_status(400) |> json(%{error: "invalid_request"})
      {:error, _} -> conn |> put_status(400) |> json(%{error: "invalid_grant"})
    end
  end

  def revoke(conn, _params) do
    OAuth.revoke_token(conn.body_params["token"], conn.body_params["client_id"])
    send_resp(conn, 200, "")
  end

  def callback_fallback(conn, _params) do
    text(
      conn,
      "Open this link with the Shroud.email mobile app to complete sign-in. If the app is not installed, sign in on the website instead."
    )
  end

  def extension_callback(conn, _params) do
    conn
    |> put_root_layout(false)
    |> put_layout(false)
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("content-security-policy", "default-src 'none'; frame-ancestors 'none'")
    |> render("extension_callback.html")
  end

  defp callback(conn, params, result) do
    uri = URI.parse(params["redirect_uri"])

    response_query =
      result
      |> Map.merge(%{state: params["state"], iss: OAuth.issuer()})
      |> URI.encode_query()

    query =
      case uri.query do
        query when query in [nil, ""] -> response_query
        query -> query <> "&" <> response_query
      end

    redirect(conn, external: URI.to_string(%{uri | query: query}))
  end

  defp invalid(conn),
    do:
      conn
      |> put_status(400)
      |> text("Invalid or expired connection request. Start again from your app.")

  defp put_private_headers(conn, _opts),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
end
