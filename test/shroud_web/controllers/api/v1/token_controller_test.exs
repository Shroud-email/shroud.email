defmodule ShroudWeb.Api.V1.TokenControllerTest do
  use ShroudWeb.ConnCase, async: true
  import Shroud.AccountsFixtures
  alias Shroud.Accounts.{UserToken, TOTP}
  alias Shroud.Repo

  describe "create/2" do
    test "creates a token with correct email/password" do
      conn = build_conn()
      password = "ShroudP@ssword!"
      user = user_fixture(%{password: password})

      conn =
        post(conn, Routes.token_path(conn, :create), %{
          "email" => user.email,
          "password" => password
        })

      %{token: token} = Repo.get_by!(UserToken, user_id: user.id)

      assert json_response(conn, 200) == %{
               "token" => Base.encode64(token)
             }
    end

    test "creates a token with correct email/password and TOTP code" do
      conn = build_conn()
      password = "ShroudP@ssword!"
      user = user_fixture(%{password: password})
      TOTP.enable_totp!(user, "totp_secret")
      user = Repo.reload!(user)
      totp_code = user.totp_secret |> NimbleTOTP.verification_code() |> String.to_integer()

      conn =
        post(conn, Routes.token_path(conn, :create), %{
          "email" => user.email,
          "password" => password,
          "totp" => totp_code
        })

      %{token: token} = Repo.get_by!(UserToken, user_id: user.id)

      assert json_response(conn, 200) == %{
               "token" => Base.encode64(token)
             }
    end

    test "fails if TOTP is enabled but no code is given" do
      conn = build_conn()
      password = "ShroudP@ssword!"
      user = user_fixture(%{password: password})
      TOTP.enable_totp!(user, "totp_secret")
      user = Repo.reload!(user)

      conn =
        post(conn, Routes.token_path(conn, :create), %{
          "email" => user.email,
          "password" => password
        })

      assert json_response(conn, 403) == %{"error" => "Invalid email, password or TOTP code"}
    end

    test "fails if TOTP is enabled but code is incorrect" do
      conn = build_conn()
      password = "ShroudP@ssword!"
      user = user_fixture(%{password: password})
      TOTP.enable_totp!(user, "totp_secret")
      user = Repo.reload!(user)

      conn =
        post(conn, Routes.token_path(conn, :create), %{
          "email" => user.email,
          "password" => password,
          "totp" => 1234
        })

      assert json_response(conn, 403) == %{"error" => "Invalid email, password or TOTP code"}
    end
  end
end
