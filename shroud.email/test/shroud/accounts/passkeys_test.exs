defmodule Shroud.Accounts.PasskeysTest do
  use Shroud.DataCase

  alias Shroud.Accounts.{PasskeyChallenge, Passkeys}
  import Shroud.AccountsFixtures
  import Shroud.PasskeyFixtures

  test "both ceremonies use the configured HTTPS endpoint origin and hostname" do
    config = Application.fetch_env!(:shroud, ShroudWeb.Endpoint)
    on_exit(fn -> ShroudWeb.Endpoint.config_change([{ShroudWeb.Endpoint, config}], []) end)

    ShroudWeb.Endpoint.config_change(
      [
        {ShroudWeb.Endpoint,
         Keyword.put(config, :url, host: "app.example.com", scheme: "https", port: 443)}
      ],
      []
    )

    assert Passkeys.origin_and_rp_id() == {"https://app.example.com", "app.example.com"}

    user = user_fixture()
    {:ok, registration} = Passkeys.begin_registration(user)
    {:ok, authentication} = Passkeys.begin_authentication()

    for {options, kind, owner} <- [
          {registration, :registration, user},
          {authentication, :authentication, nil}
        ] do
      assert {:ok, challenge} = Passkeys.consume_challenge(options.token, kind, owner)
      assert challenge.origin == "https://app.example.com"
      assert challenge.rp_id == "app.example.com"
    end
  end

  test "base64url decoding is shared and bounded at 24,000 encoded bytes" do
    assert Passkeys.decode_base64url("-_8") == {:ok, <<251, 255>>}

    assert Passkeys.decode_base64url(String.duplicate("A", 24_000)) ==
             {:ok, :binary.copy(<<0>>, 18_000)}

    for invalid <- [String.duplicate("A", 24_004), "!", nil, %{}] do
      assert Passkeys.decode_base64url(invalid) == :error
    end
  end

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
    {id, attestation, client_data} = registration_response(options)

    assert {:error, :invalid_registration} =
             Passkeys.register(user, options.token, attestation, client_data, "Laptop", <<1>>)

    assert Shroud.Accounts.list_passkeys(user) == []

    {:ok, options} = Passkeys.begin_registration(user)
    client_data = registration_client_data(options.challenge)

    assert {:error, :invalid_registration} =
             Passkeys.register(
               user,
               options.token,
               attestation,
               client_data,
               String.duplicate("X", 101)
             )

    assert {:error, :invalid_registration} =
             Passkeys.register(user, options.token, attestation, client_data, "Laptop")

    assert Shroud.Accounts.list_passkeys(user) == []

    {:ok, options} = Passkeys.begin_registration(user)
    client_data = registration_client_data(options.challenge)

    assert {:ok, saved} =
             Passkeys.register(user, options.token, attestation, client_data, "Laptop")

    assert saved.credential_id == id
    assert saved.user_id == user.id
    assert saved.label == "Laptop"
    assert {:error, _} = Passkeys.register(user, options.token, attestation, client_data, "Again")
    assert length(Shroud.Accounts.list_passkeys(user)) == 1
  end

  test "malformed, unsupported and mismatched credential keys are rejected before persistence" do
    user = user_fixture()
    {public, _} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public
    key = %{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)}

    for invalid <- [
          42,
          %{},
          Map.delete(key, -2),
          Map.put(key, -2, "not a byte string"),
          Map.put(key, -2, bytes(<<1>>)),
          Map.put(key, -1, 2),
          Map.put(key, 3, -257),
          Map.put(key, 3, -8),
          %{1 => 2, 3 => -7, -1 => 1, -2 => bytes(<<0::256>>), -3 => bytes(<<0::256>>)},
          %{1 => 3, 3 => -257, -1 => bytes(<<1>>), -2 => bytes(<<3>>)},
          %{1 => 3, 3 => -257, -1 => bytes(:binary.copy(<<255>>, 256)), -2 => bytes(<<2>>)}
        ] do
      {:ok, options} = Passkeys.begin_registration(user)
      {id, attestation, client_data} = registration_response(options, key: invalid)

      assert {:error, :invalid_registration} =
               Passkeys.register(user, options.token, attestation, client_data, "Invalid", id)

      assert Shroud.Accounts.list_passkeys(user) == []

      assert {:error, :invalid_challenge} =
               Passkeys.consume_challenge(options.token, :registration, user)
    end

    for id <- ["", :binary.copy(<<1>>, 1_025)] do
      {:ok, options} = Passkeys.begin_registration(user)
      {^id, attestation, client_data} = registration_response(options, id: id)

      assert {:error, :invalid_registration} =
               Passkeys.register(user, options.token, attestation, client_data, "Invalid", id)
    end
  end

  test "registered EC and RSA keys authenticate and persist only public fields" do
    user = user_fixture()
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})

    for {key, signer, fields} <- [
          {%{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y), -4 => bytes(private)},
           fn message -> :crypto.sign(:ecdsa, :sha256, message, [private, :secp256r1]) end,
           [-3, -2, -1, 1, 3]},
          {%{
             1 => 3,
             3 => -257,
             -1 => bytes(:binary.encode_unsigned(elem(rsa, 2))),
             -2 => bytes(:binary.encode_unsigned(elem(rsa, 3))),
             -3 => bytes(<<1>>)
           }, fn message -> :public_key.sign(message, :sha256, rsa) end, [-2, -1, 1, 3]}
        ] do
      {:ok, options} = Passkeys.begin_registration(user)
      {id, attestation, client_data} = registration_response(options, key: key)

      assert {:ok, credential} =
               Passkeys.register(user, options.token, attestation, client_data, "Key", id)

      assert {:ok, stored, ""} = CBOR.decode(credential.public_key)
      assert Enum.sort(Map.keys(stored)) == fields
      assert {:ok, authenticated} = authenticate(user, id, signer, 0)
      assert authenticated.id == user.id
    end
  end

  test "counterless credentials work, but counters cannot reset, repeat or decrease" do
    user = user_fixture()
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public
    key = %{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)}
    signer = fn message -> :crypto.sign(:ecdsa, :sha256, message, [private, :secp256r1]) end
    {:ok, options} = Passkeys.begin_registration(user)
    {id, attestation, client_data} = registration_response(options, key: key)
    {:ok, _} = Passkeys.register(user, options.token, attestation, client_data, "Key", id)

    for count <- [0, 0, 1, 5] do
      assert {:ok, _} = authenticate(user, id, signer, count)
      assert Shroud.Accounts.get_passkey(id).sign_count == count
    end

    for count <- [0, 1, 4, 5] do
      assert {:error, :invalid_assertion} = authenticate(user, id, signer, count)
      assert Shroud.Accounts.get_passkey(id).sign_count == 5
    end

    tasks = for _ <- 1..2, do: Task.async(fn -> authenticate(user, id, signer, 6) end)
    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_assertion})) == 1
    assert Shroud.Accounts.get_passkey(id).sign_count == 6
  end

  defp bytes(value), do: %CBOR.Tag{tag: :bytes, value: value}

  defp authenticate(user, id, signer, count) do
    {:ok, options} = Passkeys.begin_authentication()

    client_data =
      Jason.encode!(%{
        type: "webauthn.get",
        challenge: options.challenge,
        origin: "http://localhost:4002"
      })

    auth_data = :crypto.hash(:sha256, "localhost") <> <<0x05, count::32>>
    signature = signer.(auth_data <> :crypto.hash(:sha256, client_data))

    Passkeys.authenticate(
      options.token,
      id,
      user.passkey_handle,
      auth_data,
      signature,
      client_data
    )
  end
end
