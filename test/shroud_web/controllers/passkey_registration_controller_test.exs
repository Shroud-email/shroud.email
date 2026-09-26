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
end
