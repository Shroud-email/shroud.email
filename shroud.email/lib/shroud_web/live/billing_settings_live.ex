defmodule ShroudWeb.BillingSettingsLive do
  use ShroudWeb, :live_view

  alias Shroud.{Billing, Repo}

  import ShroudWeb.SettingsComponents, only: [input: 1]

  embed_templates "billing_settings_live/*"

  @impl true
  def mount(_params, _session, socket) do
    billing_config = Application.get_env(:shroud, :billing, [])
    price_id = billing_config[:paddle_yearly_price_id]
    client_token = billing_config[:paddle_client_token]

    {:ok,
     assign(socket,
       lifetime_form: to_form(%{"lifetime_code" => ""}),
       paddle_price_id: price_id,
       paddle_checkout_available?: configured?(price_id) and configured?(client_token)
     ), layout: {ShroudWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       current_user: Repo.reload!(socket.assigns.current_user),
       page_title:
         if(socket.assigns.live_action == :lifetime,
           do: "Lifetime signup",
           else: "Billing settings"
         )
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.billing :if={@live_action == :billing} {assigns} />
    <.lifetime :if={@live_action == :lifetime} {assigns} />
    """
  end

  @impl true
  def handle_event("lifetime_signup", %{"lifetime_code" => code}, socket) do
    case Billing.redeem_lifetime_code(code, socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_notification(:info, "You have successfully signed up for lifetime access!")
         |> push_patch(to: ~p"/settings/billing")}

      {:error, :invalid_code} ->
        {:noreply, put_notification(socket, :error, "Invalid code.")}

      {:error, :already_redeemed} ->
        {:noreply, put_notification(socket, :error, "This code has already been redeemed.")}

      {:error, :redemption_failed} ->
        {:noreply,
         put_notification(socket, :error, "We couldn't redeem this code. Please try again.")}
    end
  end

  defp configured?(value), do: is_binary(value) and value != ""
end
