defmodule ShroudWeb.CheckoutControllerTest do
  use ShroudWeb.ConnCase, async: true
  use Oban.Testing, repo: Shroud.Repo

  import Shroud.AccountsFixtures
  import ExUnit.CaptureLog

  alias Shroud.{Accounts, Repo}
  alias Shroud.Accounts.User

  # Configured in config/test.exs; the controller verifies signatures against it.
  @webhook_secret Application.compile_env!(:shroud, [:billing, :stripe_webhook_secret])
  @webhook_path "/api/webhooks/stripe"
  # 2030-01-01T00:00:00Z
  @period_end_unix 1_893_456_000
  @period_end_naive ~N[2030-01-01 00:00:00]

  # The notifier webhook is configured in config/test.exs, so user registration
  # always enqueues a "free tier" notification. To check the paid-signup
  # notification specifically, match on its content rather than just the worker.
  defp paid_signup_notification? do
    [worker: Shroud.NotifierJob]
    |> all_enqueued()
    |> Enum.any?(&(get_in(&1.args, ["payload", "content"]) =~ "paid plan"))
  end

  # Builds a Stripe-style signature header for the given payload + secret and
  # POSTs the signed event to the webhook endpoint. Mirrors the scheme verified
  # by Stripe.Webhook.construct_event: "t=<ts>,v1=<hmac_sha256(secret, ts.payload)>".
  defp post_event(conn, event, opts \\ []) do
    payload = Jason.encode!(event)
    secret = Keyword.get(opts, :secret, @webhook_secret)
    timestamp = System.system_time(:second)

    signature =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    header = Keyword.get(opts, :signature, "t=#{timestamp},v1=#{signature}")

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", header)
    |> post(@webhook_path, payload)
  end

  defp subscription_event(type, object_attrs) do
    %{
      "object" => "event",
      "type" => type,
      "data" => %{"object" => Map.merge(%{"object" => "subscription"}, object_attrs)}
    }
  end

  defp checkout_completed_event(object_attrs) do
    %{
      "object" => "event",
      "type" => "checkout.session.completed",
      "data" => %{"object" => Map.merge(%{"object" => "checkout.session"}, object_attrs)}
    }
  end

  defp reload(%User{id: id}), do: Repo.get!(User, id)

  defp paid_user(stripe_customer_id, attrs \\ %{}) do
    user_fixture(attrs)
    |> Accounts.update_stripe_details!(%{stripe_customer_id: stripe_customer_id})
  end

  describe "POST /api/webhooks/stripe signature verification" do
    test "rejects an event with an invalid signature", %{conn: conn} do
      event = subscription_event("customer.subscription.updated", %{"customer" => "cus_x"})

      conn = post_event(conn, event, signature: "t=123,v1=deadbeef")

      assert conn.status == 400
    end

    test "rejects an event signed with the wrong secret", %{conn: conn} do
      event = subscription_event("customer.subscription.updated", %{"customer" => "cus_x"})

      conn = post_event(conn, event, secret: "whsec_wrong")

      assert conn.status == 400
    end

    test "rejects an event with a missing signature header", %{conn: conn} do
      payload = Jason.encode!(subscription_event("customer.subscription.updated", %{}))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(@webhook_path, payload)

      assert conn.status == 400
    end

    test "accepts a correctly signed event", %{conn: conn} do
      event = subscription_event("customer.subscription.trial_will_end", %{"customer" => "cus_x"})

      conn = post_event(conn, event)

      assert conn.status == 200
    end
  end

  describe "checkout.session.completed" do
    test "stores the Stripe customer id on the matching user", %{conn: conn} do
      user = user_fixture()

      event =
        checkout_completed_event(%{
          "customer_email" => user.email,
          "customer" => "cus_new123"
        })

      conn = post_event(conn, event)

      assert conn.status == 200
      assert reload(user).stripe_customer_id == "cus_new123"
    end

    test "logs an error and still returns 200 for an unknown user", %{conn: conn} do
      event =
        checkout_completed_event(%{
          "customer_email" => "nobody@example.com",
          "customer" => "cus_unknown"
        })

      {conn, log} = with_log(fn -> post_event(conn, event) end)

      assert conn.status == 200
      assert log =~ "unknown user"
    end
  end

  describe "customer.subscription.* -> active" do
    test "activates the user, sets plan expiry, clears trial and notifies", %{conn: conn} do
      user = paid_user("cus_active", %{status: :trial})

      event =
        subscription_event("customer.subscription.updated", %{
          "customer" => "cus_active",
          "status" => "active",
          "current_period_end" => @period_end_unix
        })

      conn = post_event(conn, event)
      assert conn.status == 200

      updated = reload(user)
      assert updated.status == :active
      assert updated.plan_expires_at == @period_end_naive
      assert is_nil(updated.trial_expires_at)

      assert paid_signup_notification?()
    end

    test "also handles customer.subscription.created", %{conn: conn} do
      user = paid_user("cus_created", %{status: :trial})

      event =
        subscription_event("customer.subscription.created", %{
          "customer" => "cus_created",
          "status" => "active",
          "current_period_end" => @period_end_unix
        })

      assert post_event(conn, event).status == 200
      assert reload(user).status == :active
    end
  end

  describe "customer.subscription.* -> grace-period statuses" do
    for status <- ["past_due", "incomplete"] do
      test "leaves the user's plan unchanged for #{status}", %{conn: conn} do
        user = paid_user("cus_grace", %{status: :active})

        event =
          subscription_event("customer.subscription.updated", %{
            "customer" => "cus_grace",
            "status" => unquote(status)
          })

        conn = post_event(conn, event)
        assert conn.status == 200

        updated = reload(user)
        assert updated.status == :active
        refute paid_signup_notification?()
      end
    end
  end

  describe "customer.subscription.* -> cancelling statuses" do
    for status <- ["canceled", "unpaid", "incomplete_expired"] do
      test "moves the user to the free tier for #{status}", %{conn: conn} do
        user =
          paid_user("cus_cancel", %{status: :active})
          |> then(&Accounts.update_stripe_details!(&1, %{plan_expires_at: @period_end_naive}))

        event =
          subscription_event("customer.subscription.updated", %{
            "customer" => "cus_cancel",
            "status" => unquote(status)
          })

        conn = post_event(conn, event)
        assert conn.status == 200

        updated = reload(user)
        assert updated.status == :free
        assert is_nil(updated.plan_expires_at)
        assert is_nil(updated.trial_expires_at)
      end
    end

    test "customer.subscription.deleted with a canceled status frees the user", %{conn: conn} do
      user = paid_user("cus_deleted", %{status: :active})

      event =
        subscription_event("customer.subscription.deleted", %{
          "customer" => "cus_deleted",
          "status" => "canceled"
        })

      assert post_event(conn, event).status == 200
      assert reload(user).status == :free
    end
  end

  describe "webhook edge cases" do
    test "logs an error and returns 200 for an unknown customer", %{conn: conn} do
      event =
        subscription_event("customer.subscription.updated", %{
          "customer" => "cus_does_not_exist",
          "status" => "active",
          "current_period_end" => @period_end_unix
        })

      {conn, log} = with_log(fn -> post_event(conn, event) end)

      assert conn.status == 200
      assert log =~ "unknown customer"
    end

    test "ignores an unhandled event type but returns 200", %{conn: conn} do
      event =
        subscription_event("customer.subscription.paused", %{"customer" => "cus_whatever"})

      {conn, log} = with_log(fn -> post_event(conn, event) end)

      assert conn.status == 200
      assert log =~ "unhandled Stripe event"
    end
  end

  describe "GET /checkout/billing (billing portal)" do
    setup :register_and_log_in_user

    test "redirects to billing settings when the user has no Stripe customer", %{conn: conn} do
      # No Stripe API call is made when stripe_customer_id is nil.
      conn = get(conn, ~p"/checkout/billing")

      assert redirected_to(conn) == ~p"/settings/billing"
    end
  end
end
