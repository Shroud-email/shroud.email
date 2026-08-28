defmodule Shroud.Billing.Paddle do
  @moduledoc """
  Thin client for the Paddle Billing REST API (v2).

  Auth: `Authorization: Bearer <api_key>`. Base URL configurable (sandbox/prod).
  No official Elixir SDK exists, so this module owns the small REST surface
  used to create fixed checkout transactions and customer portal sessions,
  plus Paddle webhook signature verification.

  Docs: https://developer.paddle.com
  """

  @behaviour Shroud.Billing.Paddle.Client

  @spec checkout_configured?() :: boolean()
  def checkout_configured? do
    configured?(:paddle_api_key) and configured?(:paddle_yearly_price_id)
  end

  @spec checkout_price_id() :: {:ok, String.t()} | {:error, :not_configured}
  def checkout_price_id, do: configured_value(:paddle_yearly_price_id)

  @doc """
  Creates the fixed yearly-plan transaction opened by Paddle.js.

  The checkout identity is signed by the authenticated server route and stored
  as transaction custom data. Paddle copies it to the resulting subscription.
  """
  @spec create_checkout_transaction(String.t()) ::
          {:ok, %{id: String.t()}} | {:error, term()}
  def create_checkout_transaction(checkout_identity) when is_binary(checkout_identity) do
    create_checkout_transaction(checkout_identity, nil)
  end

  @impl true
  @spec create_checkout_transaction(String.t(), String.t() | nil) ::
          {:ok, %{id: String.t()}} | {:error, term()}
  def create_checkout_transaction(checkout_identity, customer_id)
      when is_binary(checkout_identity) and (is_binary(customer_id) or is_nil(customer_id)) do
    if checkout_configured?() do
      do_create_checkout_transaction(checkout_identity, customer_id)
    else
      {:error, :not_configured}
    end
  end

  defp do_create_checkout_transaction(checkout_identity, customer_id) do
    body =
      %{
        items: [%{price_id: config()[:paddle_yearly_price_id], quantity: 1}],
        custom_data: %{shroud_checkout_identity: checkout_identity}
      }
      |> maybe_put_customer_id(customer_id)

    case client() |> Req.post(url: "/transactions", json: body) do
      {:ok, %Req.Response{status: 201, body: %{"data" => %{"id" => id}}}}
      when is_binary(id) ->
        {:ok, %{id: id}}

      {:ok, %Req.Response{status: 201}} ->
        {:error, :invalid_response}

      {:ok, %Req.Response{status: status, body: resp}} ->
        {:error, {:paddle_api, status, paddle_error_code(resp)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp maybe_put_customer_id(body, customer_id) when is_binary(customer_id),
    do: Map.put(body, :customer_id, customer_id)

  defp maybe_put_customer_id(body, nil), do: body

  @impl true
  @spec get_transaction(String.t()) ::
          {:ok, %{id: String.t(), status: String.t()}} | {:error, term()}
  def get_transaction(transaction_id) when is_binary(transaction_id) do
    if configured?(:paddle_api_key) do
      case client() |> Req.get(url: "/transactions/#{transaction_id}") do
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => %{"id" => id, "status" => status}}
         }}
        when is_binary(id) and is_binary(status) ->
          {:ok, %{id: id, status: status}}

        {:ok, %Req.Response{status: 200}} ->
          {:error, :invalid_response}

        {:ok, %Req.Response{status: status, body: response}} ->
          {:error, {:paddle_api, status, paddle_error_code(response)}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Generates a fresh customer-portal session for a Paddle customer.

  Portal sessions are temporary and must not be cached — call this each time
  the user clicks "manage billing". Returns the authenticated portal URL.
  """
  @impl true
  @spec create_portal_session(String.t()) :: {:ok, %{url: String.t()}} | {:error, term()}
  def create_portal_session(customer_id) do
    if configured?(:paddle_api_key) do
      case client() |> Req.post(url: "/customers/#{customer_id}/portal-sessions", json: %{}) do
        {:ok, %Req.Response{status: 201, body: resp}} ->
          {:ok, %{url: resp["data"]["urls"]["general"]["overview"]}}

        {:ok, %Req.Response{status: status, body: resp}} ->
          {:error, {:paddle_api, status, paddle_error_code(resp)}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Verifies a Paddle webhook signature against the configured destination secret.

  Header format: `ts=<unix_ts>;h1=<hex_hmac>`. Signed payload:
  `"ts:raw_body"` (timestamp + colon + raw body), HMAC-SHA256 keyed with the
  secret, hex digest, constant-time compare. 5-second timestamp tolerance for
  replay protection.
  """
  @impl true
  @spec verify_webhook(binary(), String.t()) :: {:ok, map()} | {:error, term()}
  def verify_webhook(raw_body, signature_header)
      when is_binary(raw_body) and is_binary(signature_header) do
    with {:ok, secret} <- configured_value(:paddle_webhook_secret),
         {:ok, ts, signatures} <- parse_header(signature_header),
         :ok <- check_freshness(ts),
         true <- signature_matches?(compute_signature(secret, ts, raw_body), signatures),
         {:ok, event} when is_map(event) <- Jason.decode(raw_body) do
      {:ok, event}
    else
      {:error, :not_configured} -> {:error, :not_configured}
      {:error, :malformed} -> {:error, :malformed}
      {:error, :stale} -> {:error, :stale}
      {:error, %Jason.DecodeError{}} -> {:error, :malformed}
      {:ok, _non_object} -> {:error, :malformed}
      false -> {:error, :invalid_signature}
    end
  end

  def verify_webhook(_raw_body, _signature_header), do: {:error, :malformed}

  defp parse_header(header) do
    parsed_parts =
      header
      |> String.split(";", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))

    with {:ok, timestamp, signatures} <- collect_signature_parts(parsed_parts),
         true <- is_binary(timestamp) and signatures != [],
         {timestamp, ""} <- Integer.parse(timestamp) do
      {:ok, timestamp, Enum.reverse(signatures)}
    else
      _ -> {:error, :malformed}
    end
  end

  defp collect_signature_parts(parts) do
    Enum.reduce_while(parts, {:ok, nil, []}, fn
      ["ts", timestamp], {:ok, nil, signatures} when timestamp != "" ->
        {:cont, {:ok, timestamp, signatures}}

      ["ts", _timestamp], _acc ->
        {:halt, {:error, :malformed}}

      ["h1", signature], {:ok, timestamp, signatures} when signature != "" ->
        {:cont, {:ok, timestamp, [signature | signatures]}}

      [_unknown_key, _value], acc ->
        {:cont, acc}

      _malformed_part, _acc ->
        {:halt, {:error, :malformed}}
    end)
  end

  defp check_freshness(ts) do
    if abs(System.system_time(:second) - ts) <= 5 do
      :ok
    else
      {:error, :stale}
    end
  end

  defp compute_signature(secret, ts, raw_body) do
    :crypto.mac(:hmac, :sha256, secret, "#{ts}:#{raw_body}")
    |> Base.encode16(case: :lower)
  end

  defp constant_time_equal?(a, b) do
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end

  defp signature_matches?(expected, signatures) do
    Enum.reduce(signatures, false, fn signature, matched? ->
      constant_time_equal?(expected, signature) or matched?
    end)
  end

  defp client do
    Req.new(
      base_url: config()[:paddle_base_url],
      auth: {:bearer, config()[:paddle_api_key]},
      headers: [{"content-type", "application/json"}]
    )
  end

  # Paddle error responses are shaped as %{"error" => %{"code" => ..., ...}}.
  # See https://developer.paddle.com/errors. Returns nil for non-conforming bodies.
  defp paddle_error_code(resp) when is_map(resp) do
    get_in(resp, ["error", "code"])
  end

  defp paddle_error_code(_resp), do: nil

  defp configured?(key) do
    match?({:ok, _value}, configured_value(key))
  end

  defp configured_value(key) do
    case config()[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :not_configured}
    end
  end

  defp config do
    Application.get_env(:shroud, :billing, [])
  end
end
