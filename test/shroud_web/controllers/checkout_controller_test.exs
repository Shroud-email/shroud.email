defmodule ShroudWeb.CheckoutControllerTest do
  use ShroudWeb.ConnCase, async: false
  use Oban.Testing, repo: Shroud.Repo

  import Shroud.AccountsFixtures

  alias Shroud.Accounts.User
  alias Shroud.Repo
  alias ShroudWeb.PaddleCheckoutIdentity

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

  defp user_with_pending_checkout(attrs) do
    attrs =
      Map.merge(
        %{
          paddle_checkout_transaction_id: "txn_test",
          paddle_checkout_price_id: "pri_test_yearly"
        },
        attrs
      )

    user_fixture(attrs)
  end

  # Builds a Paddle-style signature header for the given payload + secret and
  # POSTs the signed event to the webhook endpoint. Mirrors the scheme verified
  # by Shroud.Billing.Paddle.verify_webhook/2: "ts=<ts>;h1=<hmac_sha256(secret, ts.body)>".
  defp post_event(conn, event, opts \\ []) do
    payload = Jason.encode!(event)
    post_payload(conn, payload, opts)
  end

  defp post_payload(conn, payload, opts \\ []) do
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
      assert is_nil(Repo.reload!(user).paddle_customer_id)
    end

    test "returns 400 for signed invalid JSON instead of raising", %{conn: conn} do
      conn = post_payload(conn, "not-json")
      assert response(conn, 400) == ""
    end

    test "rejects an oversized body before signature verification", %{conn: conn} do
      payload = String.duplicate("x", 1_000_001)

      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        post_payload(conn, payload)
      end
    end
  end

  describe "subscription.created (active)" do
    test "links the customer and grants active status", %{conn: conn} do
      # User starts as :free so the active transition triggers the notification
      user =
        user_with_pending_checkout(%{status: :free})

      event =
        subscription_event("active", "ctm_abc", "sub_abc",
          checkout_identity: PaddleCheckoutIdentity.sign(user.id)
        )

      conn = post_event(conn, event)
      assert response(conn, 200) == ""

      user = Repo.get!(User, user.id)
      assert user.paddle_customer_id == "ctm_abc"
      assert user.paddle_subscription_id == "sub_abc"
      assert is_nil(user.paddle_checkout_transaction_id)
      assert is_nil(user.paddle_checkout_price_id)
      assert user.status == :active
      assert user.plan_expires_at == @period_end_naive
      assert paid_signup_notification?()
    end
  end

  describe "subscription.canceled" do
    test "revokes access to free tier and records the event timestamp", %{conn: conn} do
      user =
        user_fixture(%{
          status: :active,
          paddle_customer_id: "ctm_xyz",
          paddle_subscription_id: "sub_xyz",
          paddle_price_id: "pri_test_yearly"
        })

      # Canceled subs have current_billing_period: null per Paddle docs
      event =
        subscription_event("canceled", "ctm_xyz", "sub_xyz",
          nil_billing: true,
          event_type: "subscription.canceled"
        )

      conn = post_event(conn, event)
      assert response(conn, 200) == ""

      user = Repo.get!(User, user.id)
      assert user.status == :free
      assert is_nil(user.plan_expires_at)
      # The ordering guard depends on this being persisted.
      assert user.last_paddle_event_at == ~N[2030-01-01 00:00:00.000000]
    end
  end

  describe "idempotency" do
    test "a newer duplicate active event skips the side-effect via prior_status", %{conn: conn} do
      user = user_with_pending_checkout(%{status: :free})

      # First event grants active and notifies.
      first =
        subscription_event("active", "ctm_dup", "sub_dup",
          occurred_at: "2030-01-01T00:00:00Z",
          checkout_identity: PaddleCheckoutIdentity.sign(user.id)
        )

      post_event(conn, first)
      assert paid_signup_notification?()

      # Second event: strictly newer occurred_at (so it passes stale?/2), still
      # active. The prior_status != :active guard must prevent a second notification.
      second =
        subscription_event("active", "ctm_dup", "sub_dup", occurred_at: "2030-01-02T00:00:00Z")

      post_event(conn, second)

      count =
        Enum.count(
          all_enqueued(worker: Shroud.NotifierJob),
          &(&1.args["payload"]["content"] =~ "paid plan")
        )

      assert count == 1
    end
  end

  describe "subscription.updated" do
    test "re-provisions on an updated event with a newer occurred_at", %{conn: conn} do
      user =
        user_fixture(%{
          status: :active,
          paddle_customer_id: "ctm_upd",
          paddle_subscription_id: "sub_upd",
          paddle_price_id: "pri_test_yearly"
        })

      # A renewal: subscription.updated, active, a later period end.
      event =
        subscription_event("active", "ctm_upd", "sub_upd",
          event_type: "subscription.updated",
          occurred_at: "2031-06-01T00:00:00Z",
          period_end: "2032-06-01T00:00:00Z"
        )

      conn = post_event(conn, event)
      assert response(conn, 200) == ""

      user = Repo.get!(User, user.id)
      assert user.status == :active
      assert user.plan_expires_at == ~N[2032-06-01 00:00:00]
    end
  end

  describe "subscription.past_due" do
    test "keeps the user active during the grace period", %{conn: conn} do
      user =
        user_fixture(%{
          status: :active,
          paddle_customer_id: "ctm_due",
          paddle_subscription_id: "sub_due",
          paddle_price_id: "pri_test_yearly"
        })

      event =
        subscription_event("past_due", "ctm_due", "sub_due", event_type: "subscription.past_due")

      conn = post_event(conn, event)
      assert response(conn, 200) == ""

      user = Repo.get!(User, user.id)
      # past_due retains :active so Paddle Retain can retry payment.
      assert user.status == :active
    end
  end

  describe "unknown customer / event" do
    test "subscription event without a verifiable identity returns 503 for retry", %{conn: conn} do
      event = subscription_event("active", "ctm_nope", "sub_nope")
      conn = post_event(conn, event)
      assert response(conn, 503) == ""
    end

    test "customer.created email cannot link a different Shroud account", %{conn: conn} do
      user = user_with_pending_checkout(%{status: :free})

      conn = post_event(conn, customer_created_event(user.email, "ctm_attacker_controlled"))

      assert response(conn, 200) == ""
      assert is_nil(Repo.reload!(user).paddle_customer_id)
    end

    test "signed identity is rejected when the subscription price does not match", %{conn: conn} do
      user = user_fixture(%{status: :free})

      event =
        subscription_event("active", "ctm_wrong_price", "sub_wrong_price",
          checkout_identity: PaddleCheckoutIdentity.sign(user.id),
          price_id: "pri_other"
        )

      conn = post_event(conn, event)

      assert response(conn, 503) == ""
      assert is_nil(Repo.reload!(user).paddle_customer_id)
    end

    test "signed identity is rejected when the subscription comes from another transaction", %{
      conn: conn
    } do
      user = user_with_pending_checkout(%{status: :free})

      event =
        subscription_event("active", "ctm_wrong_transaction", "sub_wrong_transaction",
          checkout_identity: PaddleCheckoutIdentity.sign(user.id),
          transaction_id: "txn_other"
        )

      conn = post_event(conn, event)

      assert response(conn, 503) == ""
      assert is_nil(Repo.reload!(user).paddle_customer_id)
    end

    test "a known customer still requires the configured subscription price", %{conn: conn} do
      user =
        user_fixture(%{
          status: :active,
          paddle_customer_id: "ctm_known_price",
          paddle_subscription_id: "sub_known_price",
          paddle_price_id: "pri_test_yearly"
        })

      event =
        subscription_event("active", "ctm_known_price", "sub_known_price",
          checkout_identity: PaddleCheckoutIdentity.sign(user.id),
          price_id: "pri_other"
        )

      conn = post_event(conn, event)

      assert response(conn, 503) == ""
      assert Repo.reload!(user).paddle_subscription_id == "sub_known_price"
    end

    test "a bound subscription keeps using its stored entitlement after catalog rotation", %{
      conn: conn
    } do
      user =
        user_fixture(%{
          status: :active,
          paddle_customer_id: "ctm_old_catalog",
          paddle_subscription_id: "sub_old_catalog",
          paddle_price_id: "pri_old_yearly"
        })

      original = Application.fetch_env!(:shroud, :billing)

      Application.put_env(
        :shroud,
        :billing,
        Keyword.put(original, :paddle_yearly_price_id, "pri_new_yearly")
      )

      on_exit(fn -> Application.put_env(:shroud, :billing, original) end)

      event =
        subscription_event("active", "ctm_old_catalog", "sub_old_catalog",
          event_type: "subscription.updated",
          price_id: "pri_old_yearly"
        )

      conn = post_event(conn, event)

      assert response(conn, 200) == ""
      assert Repo.reload!(user).status == :active
    end

    test "a new subscription cannot use another user's known customer", %{conn: conn} do
      mapped_user = user_fixture(%{status: :free, paddle_customer_id: "ctm_known_identity"})
      checkout_user = user_with_pending_checkout(%{status: :free})

      event =
        subscription_event("active", "ctm_known_identity", "sub_wrong_user",
          checkout_identity: PaddleCheckoutIdentity.sign(checkout_user.id)
        )

      conn = post_event(conn, event)

      assert response(conn, 503) == ""
      assert is_nil(Repo.reload!(mapped_user).paddle_subscription_id)
      assert is_nil(Repo.reload!(checkout_user).paddle_customer_id)
    end

    test "a returning free customer can bind a new signed subscription", %{conn: conn} do
      user =
        user_with_pending_checkout(%{
          status: :free,
          paddle_customer_id: "ctm_returning",
          paddle_subscription_id: "sub_canceled",
          paddle_price_id: "pri_test_yearly"
        })

      event =
        subscription_event("active", "ctm_returning", "sub_reactivated",
          checkout_identity: PaddleCheckoutIdentity.sign(user.id)
        )

      conn = post_event(conn, event)

      assert response(conn, 200) == ""
      updated_user = Repo.reload!(user)
      assert updated_user.paddle_subscription_id == "sub_reactivated"
      assert updated_user.status == :active
    end

    test "a recognized subscription event without data is retried", %{conn: conn} do
      event = %{
        "event_id" => "evt_#{System.unique_integer([:positive])}",
        "event_type" => "subscription.updated",
        "occurred_at" => @occurred_at
      }

      conn = post_event(conn, event)
      assert response(conn, 503) == ""
    end

    test "an unknown subscription status is retried instead of revoking access", %{conn: conn} do
      user = user_fixture(%{status: :active, paddle_customer_id: "ctm_unknown_status"})
      event = subscription_event("unexpected", "ctm_unknown_status", "sub_unknown_status")

      conn = post_event(conn, event)

      assert response(conn, 503) == ""
      assert Repo.reload!(user).status == :active
    end

    test "an unhandled event type returns 200", %{conn: conn} do
      event = %{
        "event_id" => "evt_#{System.unique_integer([:positive])}",
        "event_type" => "product.updated",
        "occurred_at" => @occurred_at,
        "data" => %{"id" => "pro_123"}
      }

      conn = post_event(conn, event)
      assert response(conn, 200) == ""
    end
  end

  describe "billing_portal/2" do
    test "redirects to /settings/billing when the user has no paddle_customer_id", %{conn: conn} do
      user = user_with_pending_checkout(%{status: :free})
      user |> User.confirm_changeset() |> Repo.update!()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/checkout/billing")
      assert redirected_to(conn) == "/settings/billing"
    end
  end

  describe "stale event ordering" do
    test "an older occurred_at after a newer one is skipped", %{conn: conn} do
      user = user_with_pending_checkout(%{status: :free})

      # Newer event: grants active.
      newer =
        subscription_event("active", "ctm_old", "sub_old",
          occurred_at: @occurred_at,
          checkout_identity: PaddleCheckoutIdentity.sign(user.id)
        )

      post_event(conn, newer)
      assert Repo.get!(User, user.id).status == :active

      # Older event: canceled — must NOT revoke (it's stale).
      older =
        subscription_event("canceled", "ctm_old", "sub_old",
          event_type: "subscription.canceled",
          occurred_at: "2029-01-01T00:00:00Z"
        )

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
    event_type = Keyword.get(opts, :event_type, "subscription.created")
    period_end = Keyword.get(opts, :period_end, @period_end_iso)
    checkout_identity = Keyword.get(opts, :checkout_identity)
    price_id = Keyword.get(opts, :price_id, "pri_test_yearly")
    transaction_id = Keyword.get(opts, :transaction_id, "txn_test")

    billing_period =
      if nil_billing do
        nil
      else
        %{"ends_at" => period_end}
      end

    %{
      "event_id" => "evt_#{System.unique_integer([:positive])}",
      "event_type" => event_type,
      "occurred_at" => occurred_at,
      "data" => %{
        "id" => sub_id,
        "transaction_id" => transaction_id,
        "status" => status,
        "customer_id" => customer_id,
        "current_billing_period" => billing_period,
        "custom_data" =>
          if(checkout_identity,
            do: %{"shroud_checkout_identity" => checkout_identity},
            else: nil
          ),
        "items" => [%{"price" => %{"id" => price_id}}]
      }
    }
  end
end
