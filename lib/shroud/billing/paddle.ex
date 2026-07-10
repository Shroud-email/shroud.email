defmodule Shroud.Billing.Paddle do
  @moduledoc """
  Thin client for the Paddle Billing REST API (v2).

  Auth: `Authorization: Bearer <api_key>`. Base URL configurable (sandbox/prod).
  No official Elixir SDK exists; the surface is three endpoints.

  Docs: https://developer.paddle.com
  """

  @behaviour Shroud.Billing.Paddle.Client

  @doc """
  Creates a checkout transaction for the yearly plan. Returns the hosted
  Paddle Checkout URL to redirect to.

  Paddle auto-creates the subscription when checkout completes.
  The email is captured by Paddle Checkout on the hosted page, not passed
  server-side — the `POST /transactions` body has no `customer` field.
  """
  @impl true
  @spec create_checkout(String.t()) :: %{checkout_url: String.t()}
  def create_checkout(_email) do
    body = %{
      items: [%{quantity: 1, price_id: config()[:paddle_yearly_price_id]}],
      collection_mode: "automatic"
    }

    {:ok, %Req.Response{status: 201, body: resp}} =
      client()
      |> Req.post(url: "/transactions", json: body)

    %{checkout_url: resp["data"]["checkout"]["url"]}
  end

  @doc """
  Generates a fresh customer-portal session for a Paddle customer.

  Portal sessions are temporary and must not be cached — call this each time
  the user clicks "manage billing". Returns the authenticated portal URL.
  """
  @impl true
  @spec create_portal_session(String.t()) :: %{url: String.t()}
  def create_portal_session(customer_id) do
    {:ok, %Req.Response{status: 201, body: resp}} =
      client()
      |> Req.post(url: "/customers/#{customer_id}/portal-sessions", json: %{})

    %{url: resp["data"]["urls"]["general"]["overview"]}
  end

  @doc """
  Verifies a Paddle webhook signature against the configured destination secret.

  Header format: `ts=<unix_ts>;h1=<hex_hmac>`. Signed payload:
  `"#ts:raw_body"` (timestamp + colon + raw body), HMAC-SHA256 keyed with the
  secret, hex digest, constant-time compare. 5-second timestamp tolerance for
  replay protection.
  """
  @impl true
  @spec verify_webhook(binary(), String.t()) :: {:ok, map()} | {:error, term()}
  def verify_webhook(raw_body, signature_header) when is_binary(signature_header) do
    with {:ok, ts, sig} <- parse_header(signature_header),
         :ok <- check_freshness(ts),
         true <- constant_time_equal?(compute_signature(ts, raw_body), sig) do
      {:ok, Jason.decode!(raw_body)}
    else
      {:error, :malformed} -> {:error, :malformed}
      {:error, :stale} -> {:error, :stale}
      false -> {:error, :invalid_signature}
    end
  end

  def verify_webhook(_raw_body, _signature_header), do: {:error, :malformed}

  defp parse_header(header) do
    parts =
      header
      |> String.split(";", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.filter(fn
        [k, _v] -> k in ["ts", "h1"]
        _ -> false
      end)
      |> Map.new(fn
        [k, v] -> {k, v}
      end)

    with %{"ts" => ts, "h1" => h1} <- parts,
         {ts_int, ""} <- Integer.parse(ts) do
      {:ok, ts_int, h1}
    else
      _ -> {:error, :malformed}
    end
  end

  defp check_freshness(ts) do
    if abs(System.system_time(:second) - ts) <= 5 do
      :ok
    else
      {:error, :stale}
    end
  end

  defp compute_signature(ts, raw_body) do
    :crypto.mac(:hmac, :sha256, config()[:paddle_webhook_secret], "#{ts}:#{raw_body}")
    |> Base.encode16(case: :lower)
  end

  defp constant_time_equal?(a, b) do
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end

  defp client do
    Req.new(
      base_url: config()[:paddle_base_url],
      auth: {:bearer, config()[:paddle_api_key]},
      headers: [{"content-type", "application/json"}]
    )
  end

  defp config do
    Application.fetch_env!(:shroud, :billing)
  end
end
