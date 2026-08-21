defmodule ShroudWeb.PaddleCheckoutIdentity do
  @moduledoc """
  Signs the application identity attached to a server-created Paddle checkout.

  Paddle webhooks authenticate Paddle as the sender; this token separately
  proves which authenticated Shroud user the checkout was created for.
  """

  @salt "paddle checkout identity"
  @max_age :infinity

  @spec sign(pos_integer()) :: String.t()
  def sign(user_id) when is_integer(user_id) and user_id > 0 do
    Phoenix.Token.sign(token_secret(), @salt, %{
      user_id: user_id,
      price_id: billing_config()[:paddle_yearly_price_id]
    })
  end

  @spec verify(String.t() | nil) ::
          {:ok, %{user_id: pos_integer(), price_id: String.t()}}
          | {:error, :expired | :invalid | :missing}
  def verify(token) do
    case Phoenix.Token.verify(token_secret(), @salt, token, max_age: @max_age) do
      {:ok, %{user_id: user_id, price_id: price_id}}
      when is_integer(user_id) and user_id > 0 and is_binary(price_id) ->
        {:ok, %{user_id: user_id, price_id: price_id}}

      {:ok, _invalid_claims} ->
        {:error, :invalid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp billing_config do
    Application.fetch_env!(:shroud, :billing)
  end

  defp token_secret do
    Application.fetch_env!(:shroud, ShroudWeb.Endpoint)[:secret_key_base]
  end
end
