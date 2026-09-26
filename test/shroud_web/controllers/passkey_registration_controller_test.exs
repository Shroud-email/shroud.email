defmodule ShroudWeb.PasskeyRegistrationControllerTest do
  use ShroudWeb.ConnCase

  alias Shroud.Accounts
  alias Shroud.Accounts.PasskeyCredential
  alias Shroud.Repo
  import Shroud.AccountsFixtures

  setup :register_and_log_in_user

  test "only a confirmed user with current password may start enrollment", %{conn: conn} do
    path = ~p"/settings/passkeys/options"
    assert json_response(post(conn, path, %{current_password: "wrong"}), 403)

    assert %{"publicKey" => %{"authenticatorSelection" => selection, "user" => user}} =
             conn
             |> post(path, %{current_password: valid_user_password()})
             |> json_response(200)

    assert selection["residentKey"] == "required"
    assert selection["userVerification"] == "required"
    assert is_binary(user["id"])

    assert redirected_to(post(build_conn(), path, %{current_password: valid_user_password()})) ==
             ~p"/users/log_in"
  end

  test "an unconfirmed signed-in user cannot begin enrollment", %{conn: conn, user: user} do
    user |> Repo.reload!() |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()

    assert redirected_to(
             post(conn, ~p"/settings/passkeys/options", %{current_password: valid_user_password()})
           ) == ~p"/users/confirm"

    assert Accounts.list_passkeys(user) == []
  end

  test "enrollment options and completion are limited independently", %{conn: conn} do
    Application.put_env(:shroud, :passkey_rate_limit_minute, div(System.system_time(:second), 60))
    on_exit(fn -> Application.delete_env(:shroud, :passkey_rate_limit_minute) end)
    source = %{conn | remote_ip: {192, 0, 2, 72}}

    for _ <- 1..30 do
      assert json_response(
               post(source, ~p"/settings/passkeys/options", %{current_password: "wrong"}),
               403
             )
    end

    assert json_response(
             post(source, ~p"/settings/passkeys/options", %{current_password: "wrong"}),
             429
           )

    for _ <- 1..60 do
      assert json_response(post(source, ~p"/settings/passkeys", %{}), 422)
    end

    assert json_response(post(source, ~p"/settings/passkeys", %{}), 429)
  end

  test "finishing enrollment requires valid, unexpired password authorization", %{
    conn: conn,
    user: user
  } do
    page = get(conn, ~p"/settings/security")
    {:ok, options} = Accounts.Passkeys.begin_registration(user)
    {id, attestation, client_data} = registration_response(options)
    encode = &Base.url_encode64(&1, padding: false)

    params = %{
      "rawId" => encode.(id),
      "attestationObject" => encode.(attestation),
      "clientDataJSON" => encode.(client_data)
    }

    assert json_response(post(recycle(page), ~p"/settings/passkeys", params), 422)

    expired_token =
      Phoenix.Token.sign(
        ShroudWeb.Endpoint,
        "passkey-challenge",
        {
          options.token,
          get_session(page, :_csrf_token)
        },
        signed_at: System.system_time(:second) - 301
      )

    assert json_response(
             post(recycle(page), ~p"/settings/passkeys", Map.put(params, "token", expired_token)),
             422
           )

    assert Accounts.list_passkeys(user) == []

    authorized =
      page
      |> recycle()
      |> post(~p"/settings/passkeys/options", %{current_password: valid_user_password()})

    %{"token" => token, "publicKey" => %{"challenge" => challenge}} =
      json_response(authorized, 200)

    {valid_id, valid_attestation, valid_client_data} =
      registration_response(%{challenge: challenge})

    assert %{"id" => _} =
             authorized
             |> recycle()
             |> post(~p"/settings/passkeys", %{
               "token" => token,
               "rawId" => encode.(valid_id),
               "attestationObject" => encode.(valid_attestation),
               "clientDataJSON" => encode.(valid_client_data)
             })
             |> json_response(200)

    assert length(Accounts.list_passkeys(user)) == 1
  end

  test "canceled or malformed enrollment creates no credential", %{conn: conn, user: user} do
    conn = post(conn, ~p"/settings/passkeys/options", %{current_password: valid_user_password()})
    token = json_response(conn, 200)["token"]

    assert json_response(
             post(recycle(conn), ~p"/settings/passkeys", %{
               "token" => token,
               "attestationObject" => "broken",
               "clientDataJSON" => "broken"
             }),
             422
           )

    assert Accounts.list_passkeys(user) == []
  end

  test "another user's credential cannot be removed", %{conn: conn, user: user} do
    other = user_fixture()
    id = :crypto.strong_rand_bytes(32)

    Repo.insert!(%PasskeyCredential{user_id: other.id, credential_id: id, public_key: <<1>>})

    conn =
      delete(conn, ~p"/settings/passkeys/#{Base.url_encode64(id, padding: false)}", %{
        current_password: valid_user_password()
      })

    assert redirected_to(conn) == ~p"/settings/security"
    assert Accounts.get_passkey(id)
    assert Accounts.list_passkeys(user) == []
  end

  test "security settings displays stored passkeys", %{conn: conn, user: user} do
    Repo.insert!(%PasskeyCredential{
      user_id: user.id,
      credential_id: :crypto.strong_rand_bytes(32),
      public_key: <<1>>,
      label: "Laptop"
    })

    response = html_response(get(conn, ~p"/settings/security"), 200)
    assert response =~ "Passkeys"
    assert response =~ "Laptop"
    assert response =~ "Add passkey"
  end

  defp registration_response(options) do
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

    client_data =
      Jason.encode!(%{
        type: "webauthn.create",
        challenge: options.challenge,
        origin: "http://localhost:4002"
      })

    {id, attestation, client_data}
  end
end
