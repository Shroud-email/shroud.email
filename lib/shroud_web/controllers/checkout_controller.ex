defmodule ShroudWeb.CheckoutController do
  use ShroudWeb, :controller
  require Logger

  alias Shroud.{Accounts, Notifier}
  alias Shroud.Billing.Paddle
  alias ShroudWeb.Plugs.CachingBodyReader

  def billing_portal(conn, _params) do
    customer_id = conn.assigns.current_user.paddle_customer_id

    if is_nil(customer_id) do
      redirect(conn, to: ~p"/settings/billing")
    else
      case Paddle.create_portal_session(customer_id) do
        {:ok, %{url: url}} ->
          conn
          |> put_status(:see_other)
          |> redirect(external: url)

        {:error, reason} ->
          Logger.error("Failed to create Paddle portal session: #{inspect(reason)}")

          Sentry.capture_message("Failed to create Paddle portal session",
            extra: %{reason: inspect(reason)}
          )

          conn
          |> put_flash(:error, "We couldn't open billing management right now. Please try again.")
          |> redirect(to: ~p"/settings/billing")
      end
    end
  end

  def webhook(conn, _params) do
    raw_body = CachingBodyReader.get_raw_body(conn)
    signature = conn |> Plug.Conn.get_req_header("paddle-signature") |> List.first("")

    case Paddle.verify_webhook(raw_body, signature) do
      {:ok, event} ->
        handle_event(event)
        send_resp(conn, 200, "")

      {:error, reason} ->
        Logger.warning("Rejected Paddle webhook: #{inspect(reason)}")
        send_resp(conn, :bad_request, "")
    end
  end

  defp handle_event(event) do
    case event["event_type"] do
      "customer.created" ->
        link_customer(event["data"])

      "subscription.created" ->
        provision_subscription(event["data"], event)

      "subscription.updated" ->
        provision_subscription(event["data"], event)

      # canceled and past_due flow through provision_subscription;
      # the status mapping table handles them (canceled→:free, past_due→:active).
      "subscription.canceled" ->
        provision_subscription(event["data"], event)

      "subscription.past_due" ->
        provision_subscription(event["data"], event)

      other ->
        Logger.warning("Received unhandled Paddle event: #{other}")
    end
  end

  defp link_customer(%{"id" => customer_id, "email" => email}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        Logger.error("Paddle customer.created for unknown user: #{email}")
        Sentry.capture_message("Paddle customer.created for unknown user", extra: %{email: email})

      user ->
        # Don't overwrite a customer_id already set for this user.
        if is_nil(user.paddle_customer_id) do
          Accounts.update_paddle_details!(user, %{paddle_customer_id: customer_id})
        end
    end
  end

  defp provision_subscription(sub, event) do
    customer_id = sub["customer_id"]

    case Accounts.get_user_by_paddle_customer_id(customer_id) do
      nil ->
        Logger.error("Paddle subscription event for unknown customer: #{customer_id}")

        Sentry.capture_message("Paddle subscription event for unknown customer",
          extra: %{customer_id: customer_id}
        )

      user ->
        event_at = parse_iso8601(event["occurred_at"])

        if stale?(event_at, user.last_paddle_event_at) do
          Logger.info(
            "Skipping stale Paddle event #{event["event_id"]} " <>
              "(#{event["occurred_at"]} <= #{user.last_paddle_event_at})"
          )
        else
          period_end = parse_period_end(sub)
          status = paddle_status_to_our_status(sub["status"])
          prior_status = user.status

          Accounts.update_paddle_details!(user, %{
            paddle_subscription_id: sub["id"],
            plan_expires_at: period_end,
            status: status,
            last_paddle_event_at: event_at
          })

          # Idempotent side-effect: only notify on the active transition.
          if status == :active and prior_status != :active do
            Notifier.notify_user_signed_up(user.email)
            Logger.notice("User #{user.email} signed up! Plan expires at #{period_end}")
          end
        end
    end
  end

  # Paddle subscription.status → our status enum.
  # active/trialing/past_due → keep/grant :active (past_due gives grace; Paddle Retain retries).
  # paused/canceled → :free.
  defp paddle_status_to_our_status(status) when status in ["active", "trialing", "past_due"],
    do: :active

  defp paddle_status_to_our_status(_status), do: :free

  defp parse_period_end(%{"current_billing_period" => %{"ends_at" => ends_at}}) do
    parse_iso8601(ends_at)
  end

  defp parse_period_end(_sub), do: nil

  # Paddle timestamps are RFC 3339 (ISO 8601) strings.
  defp parse_iso8601(nil), do: nil

  defp parse_iso8601(iso) do
    {:ok, dt, _offset} = DateTime.from_iso8601(iso)
    DateTime.to_naive(dt)
  end

  # An event is stale if we've already applied a newer-or-equal event for this subscription.
  defp stale?(incoming, last) when not is_nil(last), do: incoming <= last
  defp stale?(_incoming, nil), do: false
end
