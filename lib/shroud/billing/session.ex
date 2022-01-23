defmodule Shroud.Billing.Session do
  alias Stripe.Session
  alias Stripe.BillingPortal.Session, as: BillingSession

  @spec create_checkout!(String.t(), String.t(), String.t(), :yearly | :monthly) ::
          Stripe.Session.t()
  def create_checkout!(email, success_url, cancel_url, billing_period) do
    price =
      if billing_period == :yearly,
        do: config()[:stripe_yearly_price],
        else: config()[:stripe_monthly_price]

    {:ok, session} =
      Session.create(%{
        success_url: success_url,
        cancel_url: cancel_url,
        customer_email: email,
        mode: "subscription",
        line_items: [
          %{
            quantity: 1,
            price: price
          }
        ],
        payment_method_types: [
          "card"
        ]
      })

    session
  end

  def retrieve_checkout!(id) do
    {:ok, session} = Session.retrieve(id)
    session
  end

  def create_billing!(customer, return_url) do
    {:ok, session} = BillingSession.create(%{customer: customer, return_url: return_url})
    session
  end

  defp config do
    Application.fetch_env!(:shroud, :billing)
  end
end
