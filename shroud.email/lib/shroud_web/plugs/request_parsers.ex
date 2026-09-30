defmodule ShroudWeb.Plugs.RequestParsers do
  @moduledoc """
  Parses ordinary request bodies while preserving Paddle webhook bodies verbatim.

  Paddle signatures cover the exact request bytes. Skipping JSON decoding on that
  route also lets the webhook verifier reject a validly signed malformed payload
  without `Plug.Parsers` raising before the controller runs.
  """

  alias ShroudWeb.Plugs.CachingBodyReader

  def init(opts), do: Plug.Parsers.init(opts)

  def call(%Plug.Conn{path_info: ["api", "webhooks", "paddle"]} = conn, _opts) do
    case CachingBodyReader.cache_raw_body(conn) do
      {:ok, conn} -> conn
      {:error, :too_large} -> raise Plug.Parsers.RequestTooLargeError
      {:error, _reason} -> raise Plug.BadRequestError, message: "could not read request body"
    end
  end

  def call(conn, opts), do: Plug.Parsers.call(conn, opts)
end
