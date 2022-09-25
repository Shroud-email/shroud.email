defmodule ShroudWeb.Api.V1.DomainControllerTest do
  use ShroudWeb.ConnCase, async: true
  alias Shroud.Accounts
  import Shroud.{AccountsFixtures, DomainFixtures}
  alias Shroud.Repo

  describe "index/2" do
    setup do
      conn = build_conn()
      user = user_fixture()

      user =
        user
        |> Accounts.User.confirm_changeset()
        |> Repo.update!(returning: true)

      domain_1 = custom_domain_fixture(%{user_id: user.id})
      domain_2 = custom_domain_fixture(%{user_id: user.id, ownership_verified_at: nil})

      %{conn: conn, user: user, domain_1: domain_1, domain_2: domain_2}
    end

    test "renders a list of validated domains", %{
      conn: conn,
      user: user,
      domain_1: domain_1
    } do
      conn = authorized_get(conn, user, Routes.domain_path(conn, :index))

      assert json_response(conn, 200) == %{
               "domains" => [
                 %{
                   "domain" => domain_1.domain
                 }
               ],
               "page_number" => 1,
               "page_size" => 20,
               "total_entries" => 1,
               "total_pages" => 1
             }
    end

    test "only renders domains from the current user", %{conn: conn, user: user} do
      other_user = user_fixture()
      _other_domain = custom_domain_fixture(%{user_id: other_user.id})

      conn = authorized_get(conn, user, Routes.domain_path(conn, :index))

      assert length(json_response(conn, 200)["domains"]) == 1
    end
  end

  defp authorized_get(conn, user, path, params \\ nil) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> put_req_header("authorization", "Bearer #{Base.encode64(token)}")
    |> get(path, params)
  end
end
