defmodule ShroudWeb.Plugs.RateLimit do
  @moduledoc """
  Applies a Hammer policy using a server-derived actor key.

  Pass `:policy`, `:scale` (milliseconds), `:limit`, and a `:by` function taking
  the connection. Resolve trusted proxy identity before using `conn.remote_ip`.
  """

  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts) do
    {Keyword.fetch!(opts, :policy), Keyword.fetch!(opts, :scale), Keyword.fetch!(opts, :limit),
     Keyword.fetch!(opts, :by)}
  end

  @impl true
  def call(conn, {policy, scale, limit, by}) do
    case Shroud.RateLimit.hit({policy, by.(conn)}, scale, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(Integer.ceil_div(retry_after, 1000)))
        |> put_resp_content_type("text/plain")
        |> send_resp(429, "Too many requests. Please try again later.")
        |> halt()
    end
  end
end
