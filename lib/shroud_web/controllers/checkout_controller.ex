defmodule ShroudWeb.CheckoutController do
  use ShroudWeb, :controller
  require Logger

  alias Shroud.Accounts
  alias Shroud.Billing.Paddle
  alias ShroudWeb.PaddleCheckoutIdentity
  alias ShroudWeb.Plugs.CachingBodyReader

  @subscription_event_types [
    "subscription.created",
    "subscription.updated",
    "subscription.canceled",
    "subscription.past_due"
  ]

  @subscription_statuses ["active", "trialing", "past_due", "paused", "canceled"]

  def create(conn, _params) do
    cond do
      Accounts.paid?(conn.assigns.current_user) ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "subscription_exists"})

      Paddle.checkout_configured?() ->
        create_checkout_transaction(conn)

      true ->
        checkout_error(conn, :not_configured)
    end
  end

  defp create_checkout_transaction(conn) do
    checkout_identity = PaddleCheckoutIdentity.sign(conn.assigns.current_user.id)

    with {:ok, price_id} <- Paddle.checkout_price_id(),
         {:ok, %{id: transaction_id}} <-
           Accounts.get_or_create_paddle_checkout_transaction(
             conn.assigns.current_user.id,
             price_id,
             fn user ->
               Paddle.create_checkout_transaction(checkout_identity, user.paddle_customer_id)
             end,
             fn transaction_id ->
               Paddle.get_transaction(transaction_id)
             end
           ) do
      conn
      |> put_status(:created)
      |> json(%{transaction_id: transaction_id})
    else
      {:error, :subscription_exists} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "subscription_exists"})

      {:error, reason} ->
        checkout_error(conn, reason)
    end
  end

  defp checkout_error(conn, reason) do
    Logger.error("Failed to create Paddle checkout transaction: #{inspect(reason)}")

    Sentry.capture_message("Failed to create Paddle checkout transaction",
      extra: %{reason: inspect(reason)}
    )

    conn
    |> put_status(:bad_gateway)
    |> json(%{error: "checkout_unavailable"})
  end

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
        case handle_event(event) do
          :ok ->
            send_resp(conn, 200, "")

          {:error, reason} ->
            Logger.error("Failed to process Paddle webhook: #{inspect(reason)}")

            Sentry.capture_message("Failed to process Paddle webhook",
              extra: %{reason: inspect(reason)}
            )

            send_resp(conn, :service_unavailable, "")
        end

      {:error, reason} ->
        Logger.warning("Rejected Paddle webhook: #{inspect(reason)}")
        send_resp(conn, :bad_request, "")
    end
  end

  defp handle_event(%{"event_type" => "customer.created"}), do: :ok

  defp handle_event(%{"event_type" => event_type, "data" => subscription} = event)
       when event_type in @subscription_event_types do
    provision_subscription(subscription, event, event_type)
  end

  defp handle_event(%{"event_type" => event_type})
       when event_type in @subscription_event_types,
       do: {:error, :malformed_subscription}

  defp handle_event(%{"event_type" => event_type}) when is_binary(event_type) do
    Logger.warning("Received unhandled Paddle event: #{event_type}")
    :ok
  end

  defp handle_event(_malformed_event), do: {:error, :malformed_event}

  defp provision_subscription(subscription, event, _event_type) when is_map(subscription) do
    with {:ok, customer_id} <- required_binary(subscription, "customer_id"),
         {:ok, subscription_id} <- required_binary(subscription, "id"),
         {:ok, status} <- required_subscription_status(subscription),
         {:ok, event_at} <- parse_iso8601(event["occurred_at"]),
         {:ok, period_end} <- parse_period_end(subscription),
         {:ok, %{user_id: identity_user_id, price_id: price_id}} <-
           checkout_identity_user_id(
             subscription,
             customer_id,
             subscription_id
           ),
         {:ok, result} <-
           Accounts.apply_paddle_subscription_event(%{
             customer_id: customer_id,
             identity_user_id: identity_user_id,
             subscription_id: subscription_id,
             price_id: price_id,
             plan_expires_at: period_end,
             status: paddle_status_to_our_status(status),
             event_at: event_at
           }) do
      log_subscription_result(result, event, customer_id)
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp provision_subscription(_subscription, _event, _event_type),
    do: {:error, :malformed_subscription}

  defp checkout_identity_user_id(subscription, customer_id, subscription_id) do
    case Accounts.get_user_by_paddle_customer_id(customer_id) do
      %Shroud.Accounts.User{
        paddle_subscription_id: ^subscription_id,
        paddle_price_id: price_id,
        id: user_id
      }
      when is_binary(price_id) ->
        if subscription_has_price?(subscription, price_id) do
          {:ok, %{user_id: user_id, price_id: price_id}}
        else
          {:error, :invalid_subscription_price}
        end

      %Shroud.Accounts.User{id: user_id} ->
        verify_checkout_identity(subscription, user_id)

      nil ->
        verify_checkout_identity(subscription)
    end
  end

  defp verify_checkout_identity(subscription, expected_user_id \\ nil) do
    with token when is_binary(token) <-
           get_in(subscription, ["custom_data", "shroud_checkout_identity"]),
         {:ok, %{user_id: user_id, price_id: price_id}} <-
           PaddleCheckoutIdentity.verify(token),
         true <- is_nil(expected_user_id) or user_id == expected_user_id,
         true <- subscription_has_price?(subscription, price_id),
         {:ok, transaction_id} <- required_binary(subscription, "transaction_id"),
         %Shroud.Accounts.User{} = user <- Accounts.get_user(user_id),
         true <- user.paddle_checkout_transaction_id == transaction_id,
         true <- user.paddle_checkout_price_id == price_id do
      {:ok, %{user_id: user_id, price_id: price_id}}
    else
      _invalid_identity -> {:error, :invalid_checkout_identity}
    end
  end

  defp subscription_has_price?(%{"items" => items}, price_id) when is_list(items) do
    Enum.any?(items, &(get_in(&1, ["price", "id"]) == price_id))
  end

  defp subscription_has_price?(_subscription, _price_id), do: false

  defp required_binary(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:malformed_subscription, key}}
    end
  end

  defp required_subscription_status(subscription) do
    with {:ok, status} <- required_binary(subscription, "status"),
         true <- status in @subscription_statuses do
      {:ok, status}
    else
      _unsupported_status -> {:error, :unsupported_subscription_status}
    end
  end

  defp log_subscription_result(:applied, _event, customer_id) do
    Logger.notice("Applied Paddle subscription event for customer #{customer_id}")
  end

  defp log_subscription_result(:stale, event, _customer_id) do
    Logger.info("Skipping stale Paddle event #{event["event_id"]}")
  end

  defp log_subscription_result(:unrelated_subscription, event, customer_id) do
    Logger.warning(
      "Ignoring Paddle event #{event["event_id"]} for unrelated subscription on customer #{customer_id}"
    )
  end

  # Paddle subscription.status → our status enum.
  # active/trialing/past_due → keep/grant :active (past_due gives grace; Paddle Retain retries).
  # paused/canceled → :free.
  defp paddle_status_to_our_status(status) when status in ["active", "trialing", "past_due"],
    do: :active

  defp paddle_status_to_our_status(_status), do: :free

  defp parse_period_end(%{"current_billing_period" => %{"ends_at" => ends_at}}) do
    case parse_iso8601(ends_at) do
      {:ok, datetime} -> {:ok, NaiveDateTime.truncate(datetime, :second)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_period_end(%{"current_billing_period" => nil}), do: {:ok, nil}
  defp parse_period_end(_subscription), do: {:error, :malformed_billing_period}

  # Paddle timestamps are RFC 3339 (ISO 8601) strings.
  defp parse_iso8601(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_naive(datetime)}
      {:error, _reason} -> {:error, :malformed_timestamp}
    end
  end

  defp parse_iso8601(_iso), do: {:error, :malformed_timestamp}
end
