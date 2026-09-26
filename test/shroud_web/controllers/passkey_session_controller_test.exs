defmodule ShroudWeb.PasskeySessionControllerTest do
  use ShroudWeb.ConnCase

  alias Shroud.Accounts.PasskeyCredential
  alias Shroud.Accounts.TOTP
  alias Shroud.Accounts.User
  alias Shroud.Repo
  import Shroud.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    user = user |> User.confirm_changeset() |> Repo.update!()
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public
    id = :crypto.strong_rand_bytes(32)
    key = %{1 => 2, 3 => -7, -1 => 1, -2 => x, -3 => y}

    Repo.insert!(%PasskeyCredential{
      user_id: user.id,
      credential_id: id,
      public_key:
        key
        |> Map.new(fn {k, value} ->
          {k, if(is_binary(value), do: %CBOR.Tag{tag: :bytes, value: value}, else: value)}
        end)
        |> CBOR.encode()
    })

    %{conn: get(conn, ~p"/users/log_in"), user: user, credential_id: id, private_key: private}
  end

  test "signed passkey logs in even with TOTP enabled", context do
    TOTP.enable_totp!(context.user, TOTP.create_secret())
    options_conn = post(context.conn, ~p"/users/passkeys/options")
    options = json_response(options_conn, 200)
    assert options["publicKey"]["userVerification"] == "required"
    refute Map.has_key?(options["publicKey"], "allowCredentials")

    conn =
      post(recycle(options_conn), ~p"/users/passkeys", assertion(options, context))

    assert get_session(conn, :user_token)
    assert redirected_to(conn) == "/"
  end

  test "unconfirmed accounts retain confirmation redirect", context do
    user = Repo.update!(Ecto.Changeset.change(context.user, confirmed_at: nil))
    options_conn = post(context.conn, ~p"/users/passkeys/options")

    conn =
      post(
        recycle(options_conn),
        ~p"/users/passkeys",
        assertion(json_response(options_conn, 200), %{context | user: user})
      )

    assert redirected_to(conn) == "/users/confirm"
  end

  test "an assertion without user verification is rejected", context do
    options_conn = post(context.conn, ~p"/users/passkeys/options")
    params = assertion(json_response(options_conn, 200), context, uv: false)
    conn = post(recycle(options_conn), ~p"/users/passkeys", params)
    assert json_response(conn, 422)["error"]
    refute get_session(conn, :user_token)
  end

  test "a mismatched user handle is rejected", context do
    options_conn = post(context.conn, ~p"/users/passkeys/options")
    params = assertion(json_response(options_conn, 200), context)

    conn =
      post(
        recycle(options_conn),
        ~p"/users/passkeys",
        Map.put(
          params,
          "userHandle",
          Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        )
      )

    assert json_response(conn, 422)["error"]
    refute get_session(conn, :user_token)
  end

  test "a signed response for another origin is rejected", context do
    options_conn = post(context.conn, ~p"/users/passkeys/options")

    conn =
      post(
        recycle(options_conn),
        ~p"/users/passkeys",
        assertion(json_response(options_conn, 200), context, origin: "https://attacker.example")
      )

    assert json_response(conn, 422)["error"]
    refute get_session(conn, :user_token)
  end

  test "a consumed challenge cannot be replayed", context do
    options_conn = post(context.conn, ~p"/users/passkeys/options")
    params = assertion(json_response(options_conn, 200), context)
    assert redirected_to(post(recycle(options_conn), ~p"/users/passkeys", params)) == "/"
    conn = post(recycle(options_conn), ~p"/users/passkeys", params)
    assert json_response(conn, 422)["error"]
    refute get_session(conn, :user_token)
  end

  test "an overlapping options request does not invalidate the first assertion", context do
    first = post(context.conn, ~p"/users/passkeys/options")
    options = json_response(first, 200)
    second = post(recycle(first), ~p"/users/passkeys/options")
    assert json_response(second, 200)["token"] != options["token"]

    conn = post(recycle(second), ~p"/users/passkeys", assertion(options, context))
    assert redirected_to(conn) == "/"
  end

  test "a challenge from another browser session is rejected", context do
    page = get(context.conn, ~p"/users/log_in")
    assert is_binary(get_session(page, :_csrf_token))
    first = post(recycle(page), ~p"/users/passkeys/options")
    params = assertion(json_response(first, 200), context)
    other = post(build_conn(), ~p"/users/passkeys", params)
    assert json_response(other, 422)["error"]
    refute get_session(other, :user_token)
  end

  test "a malformed response cannot authenticate", context do
    options_conn = post(context.conn, ~p"/users/passkeys/options")
    conn = post(recycle(options_conn), ~p"/users/passkeys", %{"rawId" => "%%%"})
    assert json_response(conn, 422)["error"]
    refute get_session(conn, :user_token)
  end

  test "anonymous challenge issuance is rate limited by source address", context do
    freeze_rate_limit_minute()
    source = %{context.conn | remote_ip: {192, 0, 2, 27}}

    for _ <- 1..30 do
      assert json_response(post(source, ~p"/users/passkeys/options"), 200)
    end

    assert json_response(post(source, ~p"/users/passkeys/options"), 429)["error"]
    other = %{context.conn | remote_ip: {192, 0, 2, 28}}
    assert json_response(post(other, ~p"/users/passkeys/options"), 200)
  end

  test "only configured proxy peers can supply the client address", context do
    freeze_rate_limit_minute()
    previous_proxies = Application.fetch_env(:shroud, :passkey_trusted_proxies)
    Application.put_env(:shroud, :passkey_trusted_proxies, [{192, 0, 2, 41}])

    on_exit(fn ->
      case previous_proxies do
        {:ok, proxies} -> Application.put_env(:shroud, :passkey_trusted_proxies, proxies)
        :error -> Application.delete_env(:shroud, :passkey_trusted_proxies)
      end
    end)

    proxy = %{recycle(context.conn) | remote_ip: {192, 0, 2, 41}}
    spoofed = %{recycle(context.conn) | remote_ip: {192, 0, 2, 42}}
    header = "198.51.100.1, 198.51.100.2"

    for _ <- 1..30 do
      assert json_response(
               post(
                 put_req_header(proxy, "x-forwarded-for", header),
                 ~p"/users/passkeys/options"
               ),
               200
             )
    end

    assert json_response(
             post(put_req_header(proxy, "x-forwarded-for", header), ~p"/users/passkeys/options"),
             429
           )

    assert json_response(
             post(
               put_req_header(proxy, "x-forwarded-for", "198.51.100.3"),
               ~p"/users/passkeys/options"
             ),
             200
           )

    assert json_response(
             post(
               put_req_header(spoofed, "x-forwarded-for", header),
               ~p"/users/passkeys/options"
             ),
             200
           )
  end

  defp freeze_rate_limit_minute do
    Application.put_env(:shroud, :passkey_rate_limit_minute, div(System.system_time(:second), 60))
    on_exit(fn -> Application.delete_env(:shroud, :passkey_rate_limit_minute) end)
  end

  defp assertion(options, %{user: user, credential_id: id, private_key: private}, opts \\ []) do
    challenge = options["publicKey"]["challenge"]

    client_data =
      Jason.encode!(%{
        type: "webauthn.get",
        challenge: challenge,
        origin: Keyword.get(opts, :origin, "http://localhost:4002")
      })

    flags = if Keyword.get(opts, :uv, true), do: 0x05, else: 0x01
    auth_data = :crypto.hash(:sha256, "localhost") <> <<flags, 1::32>>

    signature =
      :crypto.sign(:ecdsa, :sha256, auth_data <> :crypto.hash(:sha256, client_data), [
        private,
        :secp256r1
      ])

    encode = &Base.url_encode64(&1, padding: false)

    %{
      "token" => options["token"],
      "rawId" => encode.(id),
      "userHandle" => encode.(user.passkey_handle),
      "authenticatorData" => encode.(auth_data),
      "clientDataJSON" => encode.(client_data),
      "signature" => encode.(signature)
    }
  end
end
