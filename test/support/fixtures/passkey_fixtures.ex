defmodule Shroud.PasskeyFixtures do
  def registration_response(options) do
    {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public
    id = :crypto.strong_rand_bytes(32)

    key = %{
      1 => 2,
      3 => -7,
      -1 => 1,
      -2 => %CBOR.Tag{tag: :bytes, value: x},
      -3 => %CBOR.Tag{tag: :bytes, value: y}
    }

    credential_data = <<0::128, byte_size(id)::16, id::binary>> <> CBOR.encode(key)
    auth_data = :crypto.hash(:sha256, "localhost") <> <<0x45, 0::32>> <> credential_data

    attestation =
      CBOR.encode(%{
        "fmt" => "none",
        "attStmt" => %{},
        "authData" => %CBOR.Tag{tag: :bytes, value: auth_data}
      })

    {id, attestation, registration_client_data(options.challenge)}
  end

  def registration_client_data(challenge) do
    Jason.encode!(%{
      type: "webauthn.create",
      challenge: challenge,
      origin: "http://localhost:4002"
    })
  end
end
