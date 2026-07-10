defmodule Shroud.Billing.Paddle.Client do
  @moduledoc """
  Behaviour for the Paddle Billing REST client, for Mox-based testing.
  See `Shroud.Billing.Paddle` for the production implementation.
  """

  @callback create_checkout(email :: String.t()) ::
              {:ok, %{checkout_url: String.t()}} | {:error, term()}

  @callback create_portal_session(customer_id :: String.t()) ::
              {:ok, %{url: String.t()}} | {:error, term()}

  @callback verify_webhook(raw_body :: binary(), signature_header :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
