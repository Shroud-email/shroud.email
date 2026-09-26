defmodule Shroud.Accounts.PasskeysTest do
  use Shroud.DataCase

  alias Shroud.Accounts.{PasskeyChallenge, Passkeys}
  import Shroud.AccountsFixtures

  test "registration challenges are fresh and bound to a user" do
    user = user_fixture()
    other = user_fixture()
    assert {:ok, first} = Passkeys.begin_registration(user)
    assert {:ok, second} = Passkeys.begin_registration(user)

    refute first.challenge == second.challenge

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(first.token, :registration, other)

    assert {:ok, challenge} = Passkeys.consume_challenge(first.token, :registration, user)
    assert challenge.bytes == Base.url_decode64!(first.challenge, padding: false)
    assert challenge.user_verification == "required"
    assert challenge.rp_id == "localhost"

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(first.token, :registration, user)
  end

  test "authentication challenges cannot be consumed as registration" do
    assert {:ok, options} = Passkeys.begin_authentication()

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(options.token, :registration, nil)

    assert {:ok, challenge} = Passkeys.consume_challenge(options.token, :authentication, nil)
    assert challenge.user_verification == "required"
    assert challenge.origin == "http://localhost:4002"
  end

  test "expired challenge cannot be consumed" do
    assert {:ok, options} = Passkeys.begin_authentication()

    {1, _} =
      from(c in PasskeyChallenge, where: c.token == ^options.token)
      |> Repo.update_all(set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])

    assert {:error, :invalid_challenge} =
             Passkeys.consume_challenge(options.token, :authentication, nil)
  end

  test "only one concurrent consumer obtains the same challenge" do
    assert {:ok, options} = Passkeys.begin_authentication()

    tasks =
      for _ <- 1..2 do
        Task.async(fn -> Passkeys.consume_challenge(options.token, :authentication, nil) end)
      end

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_challenge})) == 1
  end

  test "Wax verifies an actual attestation and persists only its public credential" do
    user = user_fixture()
    {:ok, options} = Passkeys.begin_registration(user)
    {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public
    id = :crypto.strong_rand_bytes(32)

    cose = %{
      1 => 2,
      3 => -7,
      -1 => 1,
      -2 => %CBOR.Tag{tag: :bytes, value: x},
      -3 => %CBOR.Tag{tag: :bytes, value: y}
    }

    credential_data = <<0::128, byte_size(id)::16, id::binary>> <> CBOR.encode(cose)
    auth_data = :crypto.hash(:sha256, "localhost") <> <<0x45, 0::32>> <> credential_data

    attestation =
      CBOR.encode(%{
        "fmt" => "none",
        "attStmt" => %{},
        "authData" => %CBOR.Tag{tag: :bytes, value: auth_data}
      })

    client_data =
      Jason.encode!(%{
        type: "webauthn.create",
        challenge: options.challenge,
        origin: "http://localhost:4002"
      })

    assert {:ok, saved} =
             Passkeys.register(user, options.token, attestation, client_data, "Laptop")

    assert saved.credential_id == id
    assert saved.user_id == user.id
    assert saved.label == "Laptop"
    assert {:error, _} = Passkeys.register(user, options.token, attestation, client_data, "Again")
    assert length(Shroud.Accounts.list_passkeys(user)) == 1
  end
end
