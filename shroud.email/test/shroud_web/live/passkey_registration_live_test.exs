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
    view: view,
    user: user
  } do
    view |> form("#add-passkey-form", passkey: %{current_password: "wrong"}) |> render_submit()
    assert has_element?(view, "#passkey-status[data-state=error]", "Could not authorize")
    assert has_element?(view, "#add-passkey[open]")
    refute_push_event(view, "passkey-register", _)

    options = authorize(view)

    assert options.publicKey.authenticatorSelection == %{
             residentKey: "required",
             userVerification: "required"
           }

    assert has_element?(view, "#add-passkey-submit[disabled]")
    assert has_element?(view, "#add-passkey[open]")
    render_hook(view, "passkey_status", %{token: options.token, phase: "waiting"})
    assert has_element?(view, "#passkey-status", "Waiting for your passkey")
    render_hook(view, "passkey_registered", response(options))

    assert_reply(view, %{})
    assert [credential] = Accounts.list_passkeys(user)
    assert has_element?(view, "#remove-passkey-#{credential.id}")
    assert has_element?(view, "#passkey-status", "Passkey added.")
    refute has_element?(view, "#add-passkey-submit[disabled]")
    refute has_element?(view, "#add-passkey[open]")

    view |> element("#settings-nav-account") |> render_click()
    view |> element("#settings-nav-security") |> render_click()
    assert has_element?(view, "#remove-passkey-#{credential.id}")

    view
    |> form("#remove-passkey-#{credential.id}", passkey: %{current_password: "wrong"})
    |> render_submit()

    assert Accounts.get_passkey(credential.credential_id)

    view
    |> form("#remove-passkey-#{credential.id}",
      passkey: %{current_password: valid_user_password()}
    )
    |> render_submit()

    refute has_element?(view, "#remove-passkey-#{credential.id}")
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
    view: view,
    user: user
  } do
    options = authorize(view)
    render_hook(view, "passkey_error", %{token: options.token, reason: "timeout"})
    assert has_element?(view, "#passkey-status[data-state=error]", "timed out")
    refute has_element?(view, "#add-passkey-submit[disabled]")
    render_hook(view, "passkey_registered", response(options))
    assert_reply(view, %{error: "invalid_registration"})

    options = authorize(view)
    view |> element("#settings-nav-account") |> render_click()
    assert_patch(view, ~p"/settings/account")
    view |> element("#settings-nav-security") |> render_click()
    render_hook(view, "passkey_registered", response(options))
    assert_reply(view, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []
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

  test "registration option issuance is rate limited", %{view: view} do
    Application.put_env(:shroud, :passkey_rate_limit_minute, div(System.system_time(:second), 60))
    on_exit(fn -> Application.delete_env(:shroud, :passkey_rate_limit_minute) end)

    for _ <- 1..30 do
      render_submit(view, "add_passkey", %{passkey: %{current_password: "wrong"}})
      assert has_element?(view, "#passkey-status", "Could not authorize")
    end

    render_submit(view, "add_passkey", %{passkey: %{current_password: valid_user_password()}})
    assert has_element?(view, "#passkey-status", "Too many passkey requests")
    assert Repo.aggregate("passkey_challenges", :count) == 0
  end

  test "registration verification is independently rate limited before persisting", %{
    view: view,
    user: user
  } do
    Application.put_env(:shroud, :passkey_rate_limit_minute, div(System.system_time(:second), 60))
    on_exit(fn -> Application.delete_env(:shroud, :passkey_rate_limit_minute) end)

    for _ <- 1..60 do
      render_hook(view, "passkey_registered", %{})
      assert_reply(view, %{error: "invalid_registration"})
    end

    options = authorize(view)
    render_hook(view, "passkey_registered", response(options))
    assert_reply(view, %{error: "invalid_registration"})
    assert Accounts.list_passkeys(user) == []
    assert has_element?(view, "#passkey-status[data-state=error]")
  end

  test "a user unconfirmed after mounting cannot enroll", %{view: view, user: user} do
    user |> Repo.reload!() |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()
    render_submit(view, "add_passkey", %{passkey: %{current_password: valid_user_password()}})
    assert has_element?(view, "#passkey-status[data-state=error]", "Could not authorize")
    refute_push_event(view, "passkey-register", _)
  end

  defp authorize(view) do
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
