defmodule ShroudWeb.UnsubscribeControllerTest do
  use ShroudWeb.ConnCase, async: true

  import Shroud.{AccountsFixtures, AliasesFixtures}
  alias Shroud.{Aliases, Repo}
  alias Shroud.Email.Unsubscribe

  setup do
    user = user_fixture()
    email_alias = alias_fixture(%{user_id: user.id})

    %{
      email_alias: email_alias,
      token: Unsubscribe.token(email_alias, :disable, "sender@example.com")
    }
  end

  test "anonymous URL-encoded POST disables without redirects and is repeatable", %{
    conn: conn,
    token: token,
    email_alias: email_alias
  } do
    for _ <- 1..2 do
      response =
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(~p"/unsubscribe/#{token}", "List-Unsubscribe=One-Click")

      assert response.status == 204
      assert get_resp_header(response, "location") == []
      assert get_resp_header(response, "set-cookie") == []
    end

    refute Repo.reload!(email_alias).enabled
  end

  test "multipart POST is accepted", %{conn: conn, token: token, email_alias: email_alias} do
    body =
      "--boundary\r\nContent-Disposition: form-data; name=\"List-Unsubscribe\"\r\n\r\nOne-Click\r\n--boundary--\r\n"

    conn =
      conn
      |> put_req_header("content-type", "multipart/form-data; boundary=boundary")
      |> post(~p"/unsubscribe/#{token}", body)

    assert conn.status == 204
    refute Repo.reload!(email_alias).enabled
  end

  test "GET and HEAD never mutate state", %{conn: conn, token: token, email_alias: email_alias} do
    assert get(conn, ~p"/unsubscribe/#{token}").status == 200
    assert head(conn, ~p"/unsubscribe/#{token}").status == 200
    assert Repo.reload!(email_alias).enabled
  end

  test "request logs do not expose the capability", %{conn: conn, token: token} do
    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        assert get(conn, ~p"/unsubscribe/#{token}").status == 200

        assert (conn
                |> put_req_header("content-type", "application/x-www-form-urlencoded")
                |> post(~p"/unsubscribe/#{token}", "List-Unsubscribe=One-Click")).status == 204
      end)

    refute log =~ token
  end

  test "query-only fields, malformed fields, JSON and invalid tokens are rejected", %{
    conn: conn,
    token: token,
    email_alias: email_alias
  } do
    for {path, type, body} <- [
          {"/unsubscribe/#{token}?List-Unsubscribe=One-Click",
           "application/x-www-form-urlencoded", ""},
          {"/unsubscribe/#{token}", "application/x-www-form-urlencoded",
           "List-Unsubscribe=Wrong"},
          {"/unsubscribe/#{token}", "application/json", ~s({"List-Unsubscribe":"One-Click"})},
          {"/unsubscribe/invalid", "application/x-www-form-urlencoded",
           "List-Unsubscribe=One-Click"}
        ] do
      assert (conn |> put_req_header("content-type", type) |> post(path, body)).status == 400
    end

    assert Repo.reload!(email_alias).enabled
  end

  test "old token is rejected after re-enabling", %{
    conn: conn,
    token: token,
    email_alias: email_alias
  } do
    assert {:ok, disabled} = Unsubscribe.consume(token)
    assert {:ok, _} = Aliases.update_email_alias(disabled, %{enabled: true})

    response =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(~p"/unsubscribe/#{token}", "List-Unsubscribe=One-Click")

    assert response.status == 400
    assert Repo.reload!(email_alias).enabled
  end
end
