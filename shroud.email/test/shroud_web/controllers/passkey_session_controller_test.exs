defmodule ShroudWeb.PasskeySessionControllerTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.AccountsFixtures
  alias Shroud.Accounts.{PasskeyCredential, TOTP, User}
  alias Shroud.Repo

  setup %{conn: conn} do
    user = user_fixture() |> User.confirm_changeset() |> Repo.update!()
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

    conn =
      conn |> init_test_session(%{user_return_to: "/settings/security"}) |> get(~p"/users/log_in")

    {:ok, view, _} =
      live_isolated(recycle(conn), ShroudWeb.PasskeyLoginLive,
        session: %{"csrf" => get_session(conn, :_csrf_token)}
      )

    %{conn: conn, view: view, user: user, credential_id: id, private_key: private}
  end

  test "LiveView hands a signed assertion to HTTP for session renewal, bypassing TOTP", context do
    TOTP.enable_totp!(context.user, TOTP.create_secret())
    options = options(context.view)
    assert options.publicKey.userVerification == "required"
    refute Map.has_key?(options.publicKey, :allowCredentials)
    render_hook(context.view, "passkey_assertion", assertion(options, context))
    assert has_element?(context.view, "#passkey-login-form[phx-trigger-action]")

    conn = follow_trigger_action(form(context.view, "#passkey-login-form"), context.conn)
    assert get_session(conn, :user_token)
    assert get_session(conn, :live_socket_id)
    refute get_session(conn, :_csrf_token) == get_session(context.conn, :_csrf_token)
    assert redirected_to(conn) == "/settings/security"
  end

  test "unconfirmed users retain their confirmation redirect", context do
    Repo.update!(Ecto.Changeset.change(context.user, confirmed_at: nil))
    params = assertion(options(context.view), context)
    conn = post(recycle(context.conn), ~p"/users/passkeys", params)
    assert redirected_to(conn) == "/users/confirm"
  end

  test "invalid signatures, verification flags, origins, handles, and malformed payloads never log in",
       context do
    for mutation <- [
          fn options -> assertion(options, context, uv: false) end,
          fn options -> assertion(options, context, origin: "https://attacker.example") end,
          fn options -> assertion(options, context, rp: "attacker.example") end,
          fn options -> assertion(options, context) |> Map.put("signature", "AA") end,
          fn options -> assertion(options, context) |> Map.put("userHandle", "AA") end,
          fn options -> assertion(options, context) |> Map.put("rawId", "!") end,
          fn options ->
            assertion(options, context)
            |> Map.put("clientDataJSON", String.duplicate("A", 24_004))
          end
        ] do
      conn = post(recycle(context.conn), ~p"/users/passkeys", mutation.(options(context.view)))
      assert redirected_to(conn) == "/users/log_in"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not sign in"
    end
  end

  test "consumed challenges cannot be replayed", context do
    params = assertion(options(context.view), context)

    assert redirected_to(post(recycle(context.conn), ~p"/users/passkeys", params)) ==
             "/settings/security"

    conn = post(recycle(context.conn), ~p"/users/passkeys", params)
    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :user_token)
  end

  test "challenges are browser-bound and expire", context do
    issued = options(context.view)
    params = assertion(issued, context)
    other = get(build_conn(), ~p"/users/log_in")
    conn = post(recycle(other), ~p"/users/passkeys", params)
    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :user_token)

    {:ok, token} = ShroudWeb.PasskeyChallengeToken.verify(context.conn, issued.token)

    expired =
      Phoenix.Token.sign(
        ShroudWeb.Endpoint,
        "passkey-challenge",
        {token, get_session(context.conn, :_csrf_token)},
        signed_at: System.system_time(:second) - 301
      )

    conn = post(recycle(context.conn), ~p"/users/passkeys", Map.put(params, "token", expired))
    assert redirected_to(conn) == "/users/log_in"
    refute get_session(conn, :user_token)
  end

  test "only the most recent options may trigger the login form", context do
    first = options(context.view)
    current = options(context.view)
    render_hook(context.view, "passkey_assertion", assertion(first, context))
    refute has_element?(context.view, "#passkey-login-form[phx-trigger-action]")
    render_hook(context.view, "passkey_assertion", assertion(current, context))
    assert has_element?(context.view, "#passkey-login-form[phx-trigger-action]")
  end

  test "unsupported browsers hide passkey controls and errors preserve password fallback",
       context do
    assert has_element?(context.view, "#passkey-login-controls[hidden]")
    render_hook(context.view, "passkey_supported", %{supported: true})
    refute has_element?(context.view, "#passkey-login-controls[hidden]")
    render_hook(context.view, "passkey_login_error", %{reason: "timeout"})
    assert has_element?(context.view, "#passkey-login-status", "timed out")
    refute has_element?(context.view, "#passkey-login-form[phx-trigger-action]")
    assert html_response(context.conn, 200) =~ "login-form"
  end

  test "repeated options and invalid assertions do not block a valid sign-in", context do
    for _ <- 1..31, do: assert(options(context.view).token)
    issued = options(context.view)

    for _ <- 1..61 do
      conn = post(recycle(context.conn), ~p"/users/passkeys", %{})
      assert redirected_to(conn) == "/users/log_in"
      refute get_session(conn, :user_token)
    end

    conn = post(recycle(context.conn), ~p"/users/passkeys", assertion(issued, context))
    assert redirected_to(conn) == "/settings/security"
    assert get_session(conn, :user_token)
  end

  defp options(view) do
    render_hook(view, "passkey_options")
    assert_reply(view, options)
    options
  end

  defp assertion(options, %{user: user, credential_id: id, private_key: private}, opts \\ []) do
    client_data =
      Jason.encode!(%{
        type: "webauthn.get",
        challenge: options.publicKey.challenge,
        origin: Keyword.get(opts, :origin, "http://localhost:4002")
      })

    flags = if Keyword.get(opts, :uv, true), do: 0x05, else: 0x01
    auth_data = :crypto.hash(:sha256, Keyword.get(opts, :rp, "localhost")) <> <<flags, 1::32>>

    signature =
      :crypto.sign(:ecdsa, :sha256, auth_data <> :crypto.hash(:sha256, client_data), [
        private,
        :secp256r1
      ])

    encode = &Base.url_encode64(&1, padding: false)

    %{
      "token" => options.token,
      "rawId" => encode.(id),
      "userHandle" => encode.(user.passkey_handle),
      "authenticatorData" => encode.(auth_data),
      "clientDataJSON" => encode.(client_data),
      "signature" => encode.(signature)
    }
  end
end
