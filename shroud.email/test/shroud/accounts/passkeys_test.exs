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
end
