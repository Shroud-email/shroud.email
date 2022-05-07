defmodule ShroudWeb.Api.V1.EmailAliasControllerTest do
  use ShroudWeb.ConnCase, async: true
  alias Shroud.Accounts
  import Shroud.{AccountsFixtures, AliasesFixtures}
  alias Shroud.Repo

  describe "index/2" do
    setup do
      conn = build_conn()
      user = user_fixture()

      user =
        user
        |> Accounts.User.confirm_changeset()
        |> Repo.update!(returning: true)

      email_alias_1 = alias_fixture(%{user_id: user.id})
      email_alias_2 = alias_fixture(%{user_id: user.id})
      # First email alias was created an hour ago (i.e. should come last in ordering)
      one_hour_ago =
        NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
        |> NaiveDateTime.truncate(:second)

      email_alias_1
      |> Accounts.User.inserted_at_changeset(%{inserted_at: one_hour_ago})
      |> Repo.update!()

      %{conn: conn, user: user, email_alias_1: email_alias_1, email_alias_2: email_alias_2}
    end

    test "renders a list of email aliases", %{
      conn: conn,
      user: user,
      email_alias_1: email_alias_1,
      email_alias_2: email_alias_2
    } do
      conn = authorized_get(conn, user, Routes.email_alias_path(conn, :index))

      assert json_response(conn, 200) == %{
               "email_aliases" => [
                 %{
                   "id" => email_alias_2.id,
                   "address" => email_alias_2.address,
                   "enabled" => email_alias_2.enabled,
                   "title" => email_alias_2.title,
                   "notes" => email_alias_2.notes,
                   "forwarded" => email_alias_2.forwarded,
                   "blocked" => email_alias_2.blocked,
                   "blocked_addresses" => []
                 },
                 %{
                   "id" => email_alias_1.id,
                   "address" => email_alias_1.address,
                   "enabled" => email_alias_1.enabled,
                   "title" => email_alias_1.title,
                   "notes" => email_alias_1.notes,
                   "forwarded" => email_alias_1.forwarded,
                   "blocked" => email_alias_1.blocked,
                   "blocked_addresses" => []
                 }
               ],
               "page_number" => 1,
               "page_size" => 20,
               "total_entries" => 2,
               "total_pages" => 1
             }
    end

    test "only renders aliases from the current user", %{conn: conn, user: user} do
      other_user = user_fixture()
      _other_alias = alias_fixture(%{user_id: other_user.id})

      conn = authorized_get(conn, user, Routes.email_alias_path(conn, :index))

      assert length(json_response(conn, 200)["email_aliases"]) == 2
    end

    test "handles page_size parameter", %{conn: conn, user: user, email_alias_2: email_alias_2} do
      conn =
        authorized_get(conn, user, Routes.email_alias_path(conn, :index), %{"page_size" => 1})

      assert length(json_response(conn, 200)["email_aliases"]) == 1
      assert hd(json_response(conn, 200)["email_aliases"])["id"] == email_alias_2.id
    end

    test "handles page parameter", %{conn: conn, user: user, email_alias_1: email_alias_1} do
      conn =
        authorized_get(conn, user, Routes.email_alias_path(conn, :index), %{
          "page_size" => 1,
          "page" => 2
        })

      assert length(json_response(conn, 200)["email_aliases"]) == 1
      assert hd(json_response(conn, 200)["email_aliases"])["id"] == email_alias_1.id
    end
  end

  defp authorized_get(conn, user, path, params \\ nil) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> put_req_header("authorization", "Bearer #{Base.encode64(token)}")
    |> get(path, params)
  end
end
