defmodule ShroudWeb.CheckoutControllerTest do
  use ShroudWeb.ConnCase, async: true
  use Oban.Testing, repo: Shroud.Repo

  import Shroud.AccountsFixtures

  alias Shroud.Repo
  alias Shroud.Accounts.User

  @secret Application.compile_env!(:shroud, [:billing, :paddle_webhook_secret])
  @webhook_path "/api/webhooks/paddle"
  # 2030-01-01T00:00:00Z
  @period_end_iso "2030-01-01T00:00:00Z"
  @period_end_naive ~N[2030-01-01 00:00:00]
  @occurred_at "2030-01-01T00:00:00Z"

  defp paid_signup_notification? do
    [worker: Shroud.NotifierJob]
    |> all_enqueued()
    |> Enum.any?(&(get_in(&1.args, ["payload", "content"]) =~ "paid plan"))
  end

  # Builds a Paddle-style signature header for the given payload + secret and
  # POSTs the signed event to the webhook endpoint. Mirrors the scheme verified
  # by Shroud.Billing.Paddle.verify_webhook/2: "ts=<ts>;h1=<hmac_sha256(secret, ts.body)>".
  defp post_event(conn, event, opts \\ []) do
    payload = Jason.encode!(event)
    secret = Keyword.get(opts, :secret, @secret)
    timestamp = System.system_time(:second)

    signature =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}:#{payload}")
      |> Base.encode16(case: :lower)

    header = "ts=#{timestamp};h1=#{signature}"

    conn
    |> put_req_header("paddle-signature", header)
    |> put_req_header("content-type", "application/json")
    |> post(@webhook_path, payload)
  end

  describe "webhook signature verification" do
    test "returns 400 for a bad signature", %{conn: conn} do
      event = subscription_event("active")
      conn = post_event(conn, event, secret: "wrong_secret")
      assert response(conn, 400) == ""
    end

    test "returns 200 for a valid signature", %{conn: conn} do
      user = user_fixture(%{status: :free})
      event = customer_created_event(user.email, "ctm_test")

      conn = post_event(conn, event)
      assert response(conn, 200) == ""
    end
  end

  describe "subscription.created (active)" do
    test "links the customer and grants active status", %{conn: conn} do
      # User starts as :free so the active transition triggers the notification
      user = user_fixture(%{status: :free})
      _link = post_event(conn, customer_created_event(user.email, "ctm_abc"))

      event = subscription_event("active", "ctm_abc", "sub_abc")
      conn = post_event(conn, event)
      assert response(conn, 200) == ""

      user = Repo.get!(User, user.id)
      assert user.paddle_customer_id == "ctm_abc"
      assert user.paddle_subscription_id == "sub_abc"
      assert user.status == :active
      assert user.plan_expires_at == @period_end_naive
      assert paid_signup_notification?()
    end
  end

  describe "subscription.canceled" do
    test "revokes access to free tier", %{conn: conn} do
      user = user_fixture(%{status: :active, paddle_customer_id: "ctm_xyz"})
      # Canceled subs have current_billing_period: null per Paddle docs
      event = subscription_event("canceled", "ctm_xyz", "sub_xyz", nil_billing: true)
      conn = post_event(conn, event)
      assert response(conn, 200) == ""

      user = Repo.get!(User, user.id)
      assert user.status == :free
      assert is_nil(user.plan_expires_at)
    end
  end

  describe "idempotency" do
    test "sending the same active event twice notifies only once", %{conn: conn} do
      user = user_fixture(%{status: :free})
      post_event(conn, customer_created_event(user.email, "ctm_dup"))
      event = subscription_event("active", "ctm_dup", "sub_dup")

      post_event(conn, event)
      post_event(conn, event)

      # notify_user_signed_up fires only on the active transition; the second
      # event sees user.status already :active and skips the side effect.
      count =
        Enum.count(
          all_enqueued(worker: Shroud.NotifierJob),
          &(&1.args["payload"]["content"] =~ "paid plan")
        )

      assert count <= 1
    end
  end

  describe "stale event ordering" do
    test "an older occurred_at after a newer one is skipped", %{conn: conn} do
      user = user_fixture(%{status: :free})
      post_event(conn, customer_created_event(user.email, "ctm_old"))

      # Newer event: grants active.
      newer = subscription_event("active", "ctm_old", "sub_old", occurred_at: @occurred_at)
      post_event(conn, newer)
      assert Repo.get!(User, user.id).status == :active

      # Older event: canceled — must NOT revoke (it's stale).
      older =
        subscription_event("canceled", "ctm_old", "sub_old", occurred_at: "2029-01-01T00:00:00Z")

      post_event(conn, older)
      assert Repo.get!(User, user.id).status == :active
    end
  end

  # --- Event fixtures ---

  defp customer_created_event(email, customer_id) do
    %{
      "event_id" => "evt_#{System.unique_integer([:positive])}",
      "event_type" => "customer.created",
      "occurred_at" => @occurred_at,
      "data" => %{"id" => customer_id, "email" => email}
    }
  end

  defp subscription_event(status, customer_id \\ "ctm_test", sub_id \\ "sub_test", opts \\ [])

  defp subscription_event(status, customer_id, sub_id, opts) when is_list(opts) do
    occurred_at = Keyword.get(opts, :occurred_at, @occurred_at)
    nil_billing = Keyword.get(opts, :nil_billing, false)

    billing_period =
      if nil_billing do
        nil
      else
        %{"ends_at" => @period_end_iso}
      end

    %{
      "event_id" => "evt_#{System.unique_integer([:positive])}",
      "event_type" => "subscription.created",
      "occurred_at" => occurred_at,
      "data" => %{
        "id" => sub_id,
        "status" => status,
        "customer_id" => customer_id,
        "current_billing_period" => billing_period
      }
    }
  end
end
