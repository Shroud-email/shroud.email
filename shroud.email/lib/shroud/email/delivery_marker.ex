defmodule Shroud.Email.DeliveryMarker do
  @moduledoc """
  Authenticated, encrypted delivery context carried by the email itself.
  No delivery timestamp or database correlation record is required.
  """

  alias Plug.Crypto.{KeyGenerator, MessageEncryptor}

  @header "X-Shroud-Delivery"

  def attach(email, direction, user, email_alias, recipient) do
    subject_hash = :crypto.hash(:sha256, email.subject || "") |> Base.encode64()

    marker =
      Jason.encode!([1, direction, user.id, email_alias, recipient, subject_hash])
      |> MessageEncryptor.encrypt(key(), "UNUSED")

    Swoosh.Email.header(email, @header, marker)
  end

  def verify(marker, email_alias) when is_binary(marker) and byte_size(marker) <= 2048 do
    with {:ok, payload} <- MessageEncryptor.decrypt(marker, key(), "UNUSED"),
         {:ok, [1, direction, user_id, ^email_alias, recipient, subject_hash]} <-
           Jason.decode(payload),
         true <- direction in ["outgoing", "incoming"],
         true <- is_integer(user_id) and is_binary(recipient) do
      {:ok,
       %{direction: direction, user_id: user_id, recipient: recipient, subject_hash: subject_hash}}
    else
      _ -> :error
    end
  end

  def verify(_marker, _email_alias), do: :error

  defp key do
    ShroudWeb.Endpoint.config(:secret_key_base)
    |> KeyGenerator.generate("shroud-email-delivery-marker-v1")
  end
end
