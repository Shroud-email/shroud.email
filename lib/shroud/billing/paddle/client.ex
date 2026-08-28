defmodule Shroud.Billing.Paddle.Client do
  @moduledoc """
  Contract implemented by the Paddle Billing REST client.

  `Shroud.Billing.Paddle` is the production implementation. Its HTTP boundary
  is tested with Bypass so tests exercise the real Req request and response
  handling rather than a mocked behaviour implementation.
  """

  @callback create_checkout_transaction(
              checkout_identity :: String.t(),
              customer_id :: String.t() | nil
            ) ::
              {:ok, %{id: String.t()}} | {:error, term()}

  @callback get_transaction(transaction_id :: String.t()) ::
              {:ok, %{id: String.t(), status: String.t()}} | {:error, term()}

  @callback create_portal_session(customer_id :: String.t()) ::
              {:ok, %{url: String.t()}} | {:error, term()}

  @callback verify_webhook(raw_body :: binary(), signature_header :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
