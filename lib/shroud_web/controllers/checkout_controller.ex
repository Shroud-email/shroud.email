defmodule ShroudWeb.CheckoutController do
  use ShroudWeb, :controller
  require Logger

  alias Shroud.{Accounts, Notifier}
  alias Shroud.Billing.Session
  alias ShroudWeb.Plugs.CachingBodyReader

  def index(conn, %{"period" => billing_period}) do
    # Don't use route helpers for the {CHECKOUT_SESSION_ID} template, because
    # then Phoenix will escape the brackets, which means that Stripe won't
    # substitute it properly.
    billing_period = String.to_existing_atom(billing_period)
    success_url = Routes.checkout_url(conn, :success)
    cancel_url = Routes.user_settings_url(conn, :billing)

    session =
      Session.create_checkout!(
        conn.assigns.current_user.email,
        success_url,
        cancel_url,
        billing_period
      )

    conn
    |> put_status(:see_other)
    |> redirect(external: session.url)
  end

  def success(conn, _params) do
    render(conn, "success.html")
  end

  def billing_portal(conn, _params) do
    customer_id = conn.assigns.current_user.stripe_customer_id

    if is_nil(customer_id) do
      redirect(conn, to: Routes.user_settings_path(conn, :billing))
    else
      return_url = Routes.user_settings_url(conn, :billing)
      billing_session = Session.create_billing!(customer_id, return_url)

      conn
      |> put_status(:see_other)
      |> redirect(external: billing_session.url)
    end
  end

  def webhook(conn, _params) do
    raw_body = CachingBodyReader.get_raw_body(conn)
    signature = conn |> Plug.Conn.get_req_header("stripe-signature") |> List.first("")

    case Stripe.Webhook.construct_event(raw_body, signature, webhook_secret()) do
      {:ok, %Stripe.Event{} = event} ->
        handle_webhook(event)
        # Render empty 200 response
        send_resp(conn, 200, "")

      {:error, _reason} ->
        send_resp(conn, :bad_request, "")
    end
  end

  defp handle_webhook(%Stripe.Event{} = event) do
    case event.type do
      "checkout.session.completed" ->
        handle_checkout_session_completed(event.data.object)

      "customer.subscription.created" ->
        update_subscription_status(event.data.object)

      "customer.subscription.updated" ->
        update_subscription_status(event.data.object)

      "customer.subscription.deleted" ->
        update_subscription_status(event.data.object)

      other ->
        IO.puts("Received unhandled event #{other}")
    end
  end

  defp handle_checkout_session_completed(session) do
    # TODO: send receipt email
    case Accounts.get_user_by_email(session.customer_email) do
      nil ->
        Logger.error(
          "Received checkout.session.completed webhook for unknown user: #{session.customer_email}"
        )

      user ->
        attrs = %{
          stripe_customer_id: session.customer
        }

        Accounts.update_stripe_details!(user, attrs)
    end
  end

  defp update_subscription_status(subscription) do
    case Accounts.get_user_by_stripe_id(subscription.customer) do
      nil ->
        Logger.error(
          "Received customer.subscription.updated webhook with subscription status #{subscription.status} for unknown customer: #{subscription.customer}"
        )

      user ->
        case subscription.status do
          "active" ->
            # Subscription became active (user signed up)
            current_period_end = DateTime.from_unix!(subscription.current_period_end)

            attrs = %{
              trial_expires_at: nil,
              plan_expires_at: current_period_end,
              status: :active
            }

            Accounts.update_stripe_details!(user, attrs)
            Notifier.notify_user_signed_up(user.email)
            Logger.notice("User #{user.email} signed up! Plan expires at #{current_period_end}")

          "past_due" ->
            # past_due doesn't deactivate the user's plan immediately to give them a grace period
            Logger.notice("Payment for user #{user.email} is 'past_due'")

          "incomplete" ->
            # incomplete doesn't deactivate the user's plan immediately to give them a grace period
            Logger.notice("Payment for user #{user.email} is 'incomplete'")

          other ->
            # Remaining options are incomplete_expired, canceled, unpaid. These all cancel
            # the subscription.
            # https://stripe.com/docs/api/subscriptions/object#subscription_object-status
            attrs = %{
              trial_expires_at: nil,
              plan_expires_at: nil,
              status: :inactive
            }

            Accounts.update_stripe_details!(user, attrs)
            Logger.notice("Set #{user.email} to inactive due to Stripe event '#{other}'")
        end
    end
  end

  defp webhook_secret do
    Application.fetch_env!(:shroud, :billing)[:stripe_webhook_secret]
  end
end
