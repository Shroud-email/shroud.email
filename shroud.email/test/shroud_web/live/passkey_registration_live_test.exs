defmodule ShroudWeb.PasskeyRegistrationLiveTest do
  use ShroudWeb.ConnCase

  import Phoenix.LiveViewTest
  import Shroud.AccountsFixtures
  import Shroud.PasskeyFixtures

  alias Shroud.{Accounts, Repo}
  alias Shroud.Accounts.{PasskeyChallenge, PasskeyCredential, Passkeys}

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings/security")
    render_hook(view, "passkey_supported", %{supported: true})
    %{view: view}
  end

  test "enrollment requires the current password and updates the list without navigation", %{
    conn: conn,
    view: view,
    user: user
  } do
    refute has_element?(view, "#passkey-dialog")
    view |> element("#add-passkey-button") |> render_click()
    view |> form("#add-passkey-form", passkey: %{current_password: "wrong"}) |> render_submit()

    assert has_element?(
             view,
             "#add-passkey-form #passkey-password-error",
             "Incorrect password"
           )

    assert has_element?(view, "#passkey-password[aria-invalid=true]")
    refute has_element?(view, "#notification-source [data-kind=error]")
    assert has_element?(view, "#passkey-dialog[role=dialog]")
    refute_push_event(view, "passkey-register", _)

    options = authorize(view)
    refute has_element?(view, "#passkey-password-error")

    assert options.publicKey.authenticatorSelection == %{
             residentKey: "required",
             userVerification: "required"
           }

    assert has_element?(view, "#passkey-confirm[disabled]")
    assert has_element?(view, "#passkey-dialog")
    render_hook(view, "passkey_status", %{token: options.token, phase: "waiting"})
    assert has_element?(view, "#passkey-dialog-status", "Waiting for your passkey")
    render_hook(view, "passkey_registered", response(options))

    assert_reply(view, %{})
    assert [credential] = Accounts.list_passkeys(user)
    assert has_element?(view, "#remove-passkey-button-#{credential.id}")
    assert has_element?(view, "#passkey-status", "Passkey added.")
    refute has_element?(view, "#passkey-dialog")

    view = navigate_settings(view, conn, :account, ~p"/settings/account")
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    assert has_element?(view, "#remove-passkey-button-#{credential.id}")
    refute has_element?(view, "#passkey-dialog")
    view |> element("#remove-passkey-button-#{credential.id}") |> render_click()

    view
    |> form("#remove-passkey-#{credential.id}", passkey: %{current_password: "wrong"})
    |> render_submit()

    assert Accounts.get_passkey(credential.credential_id)
    assert has_element?(view, "#passkey-dialog")

    assert has_element?(
             view,
             "#remove-passkey-#{credential.id} #passkey-password-error",
             "Incorrect password"
           )

    assert has_element?(view, "#passkey-password[aria-invalid=true]")
    refute has_element?(view, "#notification-source [data-kind=error]")

    view
    |> form("#remove-passkey-#{credential.id}",
      passkey: %{current_password: valid_user_password()}
    )
    |> render_submit()

    refute has_element?(view, "#remove-passkey-button-#{credential.id}")
    refute has_element?(view, "#passkey-dialog")
    assert Accounts.list_passkeys(user) == []
  end

  test "completion without authorization, in another socket, or after expiry saves nothing", %{
    conn: conn,
    view: view,
    user: user
  } do
    {:ok, unauthenticated_options} = Passkeys.begin_registration(user)

    render_hook(
      view,
      "passkey_registered",
      response(%{
        token: Base.url_encode64(unauthenticated_options.token, padding: false),
        publicKey: %{challenge: unauthenticated_options.challenge}
      })
    )

    assert_reply(view, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []

    authorized = authorize(view)
    {:ok, other, _} = live(conn, ~p"/settings/security")
    render_hook(other, "passkey_registered", response(authorized))
    assert_reply(other, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []

    Repo.get_by!(PasskeyChallenge, token: Base.url_decode64!(authorized.token, padding: false))
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    render_hook(view, "passkey_registered", response(authorized))
    assert_reply(view, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []
  end

  test "cancellation and tab navigation invalidate outstanding enrollment", %{
    conn: conn,
    view: view,
    user: user
  } do
    options = authorize(view)
    render_hook(view, "passkey_error", %{token: options.token, reason: "timeout"})
    assert has_element?(view, "#passkey-dialog-status", "timed out")
    refute has_element?(view, "#passkey-confirm[disabled]")
    render_hook(view, "passkey_registered", response(options))
    assert_reply(view, %{error: "invalid_registration"})

    options = authorize(view)
    monitor = Process.monitor(view.pid)
    view = navigate_settings(view, conn, :account, ~p"/settings/account")
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute Repo.get_by(PasskeyChallenge, token: Base.url_decode64!(options.token, padding: false))
    view = navigate_settings(view, conn, :security, ~p"/settings/security")
    render_hook(view, "passkey_registered", response(options))
    assert_reply(view, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []
  end

  test "closing the dialog cancels pending enrollment and rejects a late result", %{
    view: view,
    user: user
  } do
    options = authorize(view)
    view |> element("#passkey-dialog") |> render_hook("hide", %{})
    refute has_element?(view, "#passkey-dialog")
    assert_push_event(view, "passkey-cancel", %{})

    render_hook(view, "passkey_registered", response(options))
    assert_reply(view, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []

    view |> element("#add-passkey-button") |> render_click()
    assert has_element?(view, "#passkey-dialog")
    assert has_element?(view, "#add-passkey-form")
    assert has_element?(view, "#passkey-confirm:not([disabled])")
    refute has_element?(view, "#passkey-password-error")

    render_hook(view, "passkey_registered", response(authorize(view)))
    assert_reply(view, %{})
    assert [_credential] = Accounts.list_passkeys(user)
  end

  test "malformed responses consume authorization and cannot be replayed", %{
    view: view,
    user: user
  } do
    options = authorize(view)
    valid = response(options)
    render_hook(view, "passkey_registered", Map.put(valid, :attestationObject, "!"))
    assert_reply(view, %{error: "invalid_registration"})
    render_hook(view, "passkey_registered", valid)
    assert_reply(view, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []
  end

  test "another user's credential cannot be removed", %{view: view, user: user} do
    other = user_fixture()
    id = :crypto.strong_rand_bytes(32)
    Repo.insert!(%PasskeyCredential{user_id: other.id, credential_id: id, public_key: <<1>>})

    render_submit(view, "remove_passkey", %{
      credential_id: Base.url_encode64(id, padding: false),
      passkey: %{current_password: valid_user_password()}
    })

    assert Accounts.get_passkey(id)
    assert Accounts.list_passkeys(user) == []
  end

  test "removal errors are local to the selected passkey", %{conn: conn, user: user} do
    first =
      Repo.insert!(%PasskeyCredential{
        user_id: user.id,
        credential_id: :crypto.strong_rand_bytes(32),
        public_key: <<1>>
      })

    second =
      Repo.insert!(%PasskeyCredential{
        user_id: user.id,
        credential_id: :crypto.strong_rand_bytes(32),
        public_key: <<2>>
      })

    {:ok, view, _} = live(conn, ~p"/settings/security")
    refute has_element?(view, "#passkey-dialog")
    view |> element("#remove-passkey-button-#{second.id}") |> render_click()

    view
    |> form("#remove-passkey-#{second.id}", passkey: %{current_password: "wrong"})
    |> render_submit()

    refute has_element?(view, "#remove-passkey-#{first.id}")

    assert has_element?(
             view,
             "#remove-passkey-#{second.id} #passkey-password-error",
             "Incorrect password"
           )

    refute has_element?(view, "#notification-source [data-kind=error]")
    assert length(Accounts.list_passkeys(user)) == 2

    view |> element("#passkey-dialog") |> render_hook("hide", %{})
    refute has_element?(view, "#passkey-dialog")
    view |> element("#remove-passkey-button-#{first.id}") |> render_click()
    refute has_element?(view, "#passkey-password-error")
  end

  test "invalid responses below the limit do not block subsequent authorized enrollment", %{
    view: view,
    user: user
  } do
    for _ <- 1..2 do
      render_hook(view, "passkey_registered", %{})
      assert_reply(view, %{error: "invalid_registration"})
    end

    assert Accounts.list_passkeys(user) == []
    options = authorize(view)
    render_hook(view, "passkey_registered", response(options))
    assert_reply(view, %{})
    assert [_credential] = Accounts.list_passkeys(user)
  end

  test "a user unconfirmed after mounting cannot enroll", %{view: view, user: user} do
    user |> Repo.reload!() |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()
    render_submit(view, "add_passkey", %{passkey: %{current_password: valid_user_password()}})
    assert has_element?(view, "#passkey-status[data-state=error]", "Could not authorize")
    refute_push_event(view, "passkey-register", _)
  end

  test "unsupported browsers see an explanation without an add button", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings/security")
    refute has_element?(view, "#add-passkey-button")
    render_hook(view, "passkey_supported", %{supported: true})
    assert has_element?(view, "#add-passkey-button")
    render_hook(view, "passkey_supported", %{supported: false})
    refute has_element?(view, "#add-passkey-button")
    refute has_element?(view, "#passkey-dialog")
    assert has_element?(view, "#passkey-status", "This browser does not support passkeys")
  end

  test "malformed passwords fail inline without crashing or authorizing enrollment", %{
    view: view,
    user: user
  } do
    view |> element("#add-passkey-button") |> render_click()

    for value <- [
          nil,
          "unexpected",
          [],
          %{},
          %{"current_password" => []},
          %{"current_password" => String.duplicate("x", 73)}
        ] do
      # Each malformed-input case tests validation, independently of throttling.
      Shroud.RateLimit.set({{:security, :passkey}, {:account, user.id}}, 60_000, 0)
      render_submit(view, "add_passkey", %{"passkey" => value})
      assert has_element?(view, "#passkey-password-error", "Incorrect password")
      refute_push_event(view, "passkey-register", _)
    end

    Shroud.RateLimit.set({{:security, :passkey}, {:account, user.id}}, 60_000, 0)
    render_hook(view, "passkey_registered", response(authorize(view)))
    assert_reply(view, %{})
    [credential] = Accounts.list_passkeys(user)
    view |> element("#remove-passkey-button-#{credential.id}") |> render_click()

    for value <- ["unexpected", [], %{"current_password" => %{}}] do
      render_submit(view, "remove_passkey", %{
        "credential_id" => Base.url_encode64(credential.credential_id, padding: false),
        "passkey" => value
      })

      assert has_element?(view, "#passkey-password-error", "Incorrect password")
      assert Accounts.get_passkey(credential.credential_id)
    end
  end

  defp navigate_settings(view, conn, action, path) do
    {:ok, next, _} =
      view |> element("#settings-nav-#{action}") |> render_click() |> follow_redirect(conn, path)

    next
  end

  defp authorize(view) do
    if !has_element?(view, "#add-passkey-form") do
      view |> element("#add-passkey-button") |> render_click()
    end

    view
    |> form("#add-passkey-form", passkey: %{current_password: valid_user_password()})
    |> render_submit()

    assert_push_event(view, "passkey-register", options)
    # LiveViewTest bypasses the websocket serializer; ensure binary tokens never reach JSON.
    assert Jason.decode!(Jason.encode!(options))["token"] == options.token
    options
  end

  defp response(options) do
    {id, attestation, client_data} =
      registration_response(%{challenge: options.publicKey.challenge})

    %{
      token: options.token,
      rawId: Base.url_encode64(id, padding: false),
      attestationObject: Base.url_encode64(attestation, padding: false),
      clientDataJSON: Base.url_encode64(client_data, padding: false)
    }
  end
end
