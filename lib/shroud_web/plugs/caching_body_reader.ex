defmodule ShroudWeb.Plugs.CachingBodyReader do
  @moduledoc """
  Reads the raw request body and caches it. This is needed when verifying the signature
  for webhooks from 3rd party services like Stripe.

  This module is intended to be used as the `:body_reader` option of `Plug.Parsers`.
  Note that caching is only enabled for specific paths. See `enabled_for?/1`.

  See https://github.com/phoenixframework/phoenix/issues/459#issuecomment-862203762.
  """

  @raw_body_key :shroud_raw_body

  def read_body(%Plug.Conn{} = conn, opts \\ []) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, binary, conn} ->
        {:ok, binary, maybe_store_body_chunk(conn, binary)}

      {:more, binary, conn} ->
        {:more, binary, maybe_store_body_chunk(conn, binary)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enabled_for?(conn) do
    case conn.path_info do
      ["api", "webhooks" | _rest] -> true
      _ -> false
    end
  end

  defp maybe_store_body_chunk(conn, chunk) do
    if enabled_for?(conn) do
      store_body_chunk(conn, chunk)
    else
      conn
    end
  end

  def store_body_chunk(%Plug.Conn{} = conn, chunk) when is_binary(chunk) do
    chunks = conn.private[@raw_body_key] || []
    Plug.Conn.put_private(conn, @raw_body_key, [chunk | chunks])
  end

  def get_raw_body(%Plug.Conn{} = conn) do
    case conn.private[@raw_body_key] do
      nil -> nil
      chunks -> chunks |> Enum.reverse() |> Enum.join("")
    end
  end
end
