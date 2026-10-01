defmodule ShroudWeb.Plugs.RateLimit do
  @moduledoc """
  Applies a Hammer policy using a server-derived actor key.

  Pass `:policy`, `:scale` (milliseconds), `:limit`, and a `:by` function taking
  the connection. Resolve trusted proxy identity before using `conn.remote_ip`.
  """

  @behaviour Plug
  import Plug.Conn
  alias Shroud.Accounts

  @impl true
  def init(mode) when mode in [:global, :routes], do: mode

  def init(opts) do
    {Keyword.fetch!(opts, :policy), Keyword.fetch!(opts, :scale), Keyword.fetch!(opts, :limit),
     Keyword.fetch!(opts, :by)}
  end

  @impl true
  def call(%{method: method, path_info: ["_health"]} = conn, :global)
      when method in ["GET", "HEAD"], do: conn

  def call(%{method: "POST", path_info: ["api", "webhooks", "paddle"]} = conn, :global),
    do: conn

  def call(conn, :global), do: enforce(conn, :http, {:ip, conn.remote_ip})

  def call(conn, :routes) do
    # Phoenix decodes segments for routing, but pipeline plugs receive the raw
    # path. Decode only the policy-selection copy, not the routed connection.
    policies(%{conn | path_info: Enum.map(conn.path_info, &URI.decode/1)})
    |> Enum.reduce_while(conn, fn {policy, actor}, conn ->
      conn = enforce(conn, policy, actor)
      if conn.halted, do: {:halt, conn}, else: {:cont, conn}
    end)
  end

  def call(conn, {policy, scale, limit, by}) do
    result = Shroud.RateLimit.hit({policy, by.(conn)}, scale, limit)
    respond(conn, result)
  end

  def enforce(%{halted: true} = conn, _policy, _actor), do: conn
  def enforce(conn, policy, actor), do: respond(conn, Shroud.RateLimit.check(policy, actor))

  def respond(conn, result) do
    case result do
      {:allow, _count} ->
        conn

      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(Integer.ceil_div(retry_after, 1000)))
        |> reject(429, "Too many requests. Please try again later.")

      {:error, :unavailable} ->
        reject(conn, 503, "Please try again later.")
    end
  end

  defp reject(conn, status, message) do
    {content_type, body} =
      case Enum.map(conn.path_info, &URI.decode/1) do
        ["api" | _] -> {"application/json", Jason.encode!(%{error: message})}
        ["checkout", "paddle"] -> {"application/json", Jason.encode!(%{error: message})}
        _ -> {"text/plain", message}
      end

    conn |> put_resp_content_type(content_type) |> send_resp(status, body) |> halt()
  end

  defp policies(%{method: "POST", path_info: path} = conn)
       when path in [["users", "log_in"], ["users", "passkeys"], ["api", "v1", "token"]],
       do: [ip_policy(conn, :sign_in)]

  defp policies(%{method: "POST", path_info: ["users", "totp"]} = conn) do
    account =
      with %{"email" => email} <- get_session(conn, :totp_pending_user_params),
           %{id: id} <- Accounts.get_user_by_email(email) do
        [{:second_factor, {:account, id}}]
      else
        _ -> []
      end

    [ip_policy(conn, :second_factor) | account]
  end

  defp policies(%{method: "POST", path_info: path} = conn)
       when path in [["users", "register"], ["users", "reset_password"], ["users", "confirm"]],
       do: [ip_policy(conn, :account_email) | account_policy(conn, :account_email)]

  defp policies(%{method: "PUT", path_info: ["users", "reset_password", _]} = conn),
    do: [ip_policy(conn, :credentials)]

  defp policies(%{method: "PUT", path_info: ["settings", "password"]} = conn),
    do: [ip_policy(conn, :credentials) | account_policy(conn, :credentials)]

  defp policies(%{method: "GET", path_info: ["proxy"]} = conn),
    do: [ip_policy(conn, :image_proxy)]

  defp policies(%{method: "GET", path_info: ["checkout", "billing"]} = conn),
    do: account_policy(conn, :billing)

  defp policies(%{method: "POST", path_info: ["checkout", "paddle"]} = conn),
    do: account_policy(conn, :billing)

  defp policies(%{path_info: ["api", "v1", resource | _]} = conn)
       when resource in ["aliases", "domains"], do: account_policy(conn, :api)

  defp policies(_conn), do: []

  defp ip_policy(conn, policy), do: {policy, {:ip, conn.remote_ip}}

  defp account_policy(%{assigns: %{current_user: %{id: id}}}, policy),
    do: [{policy, {:account, id}}]

  defp account_policy(_conn, _policy), do: []
end
