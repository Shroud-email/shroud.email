defmodule ShroudWeb.CheckoutCreationControllerTest do
  use ShroudWeb.ConnCase, async: false

  import Shroud.AccountsFixtures

  alias Shroud.Accounts.User
  alias Shroud.Repo
  alias ShroudWeb.PaddleCheckoutIdentity

  setup do
    bypass = Bypass.open()
    original = Application.fetch_env!(:shroud, :billing)

    Application.put_env(
      :shroud,
      :billing,
      Keyword.merge(original,
        paddle_base_url: "http://localhost:#{bypass.port}",
        paddle_api_key: "test_key"
      )
    )

    on_exit(fn -> Application.put_env(:shroud, :billing, original) end)
    {:ok, bypass: bypass}
  end

  test "creates a fixed-price transaction for the authenticated user", %{
    conn: conn,
    bypass: bypass
  } do
    user = user_fixture(%{status: :free}) |> User.confirm_changeset() |> Repo.update!()

    Bypass.expect_once(bypass, "POST", "/transactions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      identity = request["custom_data"]["shroud_checkout_identity"]

      assert request["items"] == [%{"price_id" => "pri_test_yearly", "quantity" => 1}]

      assert {:ok, %{user_id: user_id, price_id: "pri_test_yearly"}} =
               PaddleCheckoutIdentity.verify(identity)

      assert user_id == user.id

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(201, Jason.encode!(%{"data" => %{"id" => "txn_123"}}))
    end)

    conn = conn |> log_in_user(user) |> post(~p"/checkout/paddle")

    assert json_response(conn, 201) == %{"transaction_id" => "txn_123"}
    assert Repo.reload!(user).paddle_checkout_transaction_id == "txn_123"
  end

  test "requires authentication", %{conn: conn} do
    conn = post(conn, ~p"/checkout/paddle")
    assert redirected_to(conn) == ~p"/users/log_in"
  end

  test "binds a returning free user to their existing Paddle customer", %{
    conn: conn,
    bypass: bypass
  } do
    user =
      user_fixture(%{status: :free, paddle_customer_id: "ctm_returning"})
      |> User.confirm_changeset()
      |> Repo.update!()

    Bypass.expect_once(bypass, "POST", "/transactions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      assert request["customer_id"] == "ctm_returning"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(201, Jason.encode!(%{"data" => %{"id" => "txn_returning"}}))
    end)

    conn = conn |> log_in_user(user) |> post(~p"/checkout/paddle")

    assert json_response(conn, 201) == %{"transaction_id" => "txn_returning"}
  end

  test "does not let an active user create another subscription", %{conn: conn} do
    user =
      user_fixture(%{status: :active, paddle_customer_id: "ctm_paid"})
      |> User.confirm_changeset()
      |> Repo.update!()

    conn = conn |> log_in_user(user) |> post(~p"/checkout/paddle")

    assert json_response(conn, 409) == %{"error" => "subscription_exists"}
  end

  test "reuses a pending checkout transaction across requests", %{conn: conn, bypass: bypass} do
    user = user_fixture(%{status: :free}) |> User.confirm_changeset() |> Repo.update!()

    Bypass.expect_once(bypass, "POST", "/transactions", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(201, Jason.encode!(%{"data" => %{"id" => "txn_pending"}}))
    end)

    first_conn = conn |> log_in_user(user) |> post(~p"/checkout/paddle")

    Bypass.expect_once(bypass, "GET", "/transactions/txn_pending", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{"data" => %{"id" => "txn_pending", "status" => "draft"}})
      )
    end)

    second_conn = build_conn() |> log_in_user(user) |> post(~p"/checkout/paddle")

    assert json_response(first_conn, 201) == %{"transaction_id" => "txn_pending"}
    assert json_response(second_conn, 201) == %{"transaction_id" => "txn_pending"}
  end

  test "replaces a canceled pending checkout", %{conn: conn, bypass: bypass} do
    user =
      user_fixture(%{
        status: :free,
        paddle_checkout_transaction_id: "txn_canceled",
        paddle_checkout_price_id: "pri_old"
      })
      |> User.confirm_changeset()
      |> Repo.update!()

    Bypass.expect(bypass, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/transactions/txn_canceled"} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{"data" => %{"id" => "txn_canceled", "status" => "canceled"}})
          )

        {"POST", "/transactions"} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(201, Jason.encode!(%{"data" => %{"id" => "txn_new"}}))
      end
    end)

    conn = conn |> log_in_user(user) |> post(~p"/checkout/paddle")

    assert json_response(conn, 201) == %{"transaction_id" => "txn_new"}
    assert Repo.reload!(user).paddle_checkout_transaction_id == "txn_new"
    assert Repo.reload!(user).paddle_checkout_price_id == "pri_test_yearly"
  end
end
