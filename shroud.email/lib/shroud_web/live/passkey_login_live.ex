defmodule ShroudWeb.PasskeyLoginLive do
  use Phoenix.LiveView, layout: false
  on_mount(ShroudWeb.RateLimitLive)

  use Phoenix.VerifiedRoutes,
    endpoint: ShroudWeb.Endpoint,
    router: ShroudWeb.Router,
    statics: ShroudWeb.static_paths()

  alias Shroud.Accounts.Passkeys
  alias ShroudWeb.PasskeyChallengeToken

  @fields ~w(token rawId userHandle authenticatorData signature clientDataJSON)

  @impl true
  def mount(_params, %{"csrf" => csrf}, socket) when is_binary(csrf) do
    {:ok,
     socket
     |> assign(:csrf, csrf)
     |> assign(:passkey_supported, false)
     |> assign(:current_token, nil)
     |> assign(:error, nil)
     |> assign(:trigger_action, false)
     |> assign(:fields, @fields)
     |> assign(:form, to_form(empty_assertion()))}
  end

  @impl true
  def handle_event("passkey_supported", %{"supported" => supported}, socket) do
    {:noreply, assign(socket, :passkey_supported, supported == true)}
  end

  def handle_event("passkey_options", _params, socket) do
    {:ok, options} = Passkeys.begin_authentication()
    signed = PasskeyChallengeToken.sign(socket.assigns.csrf, options.token)

    {:reply,
     %{
       token: signed,
       publicKey: %{
         challenge: options.challenge,
         rpId: options.rp_id,
         userVerification: "required",
         timeout: 300_000
       }
     }, assign(socket, current_token: signed, error: nil)}
  end

  def handle_event("passkey_assertion", params, socket) do
    with token when is_binary(token) <- params["token"],
         true <- secure_token_match?(token, socket.assigns.current_token),
         true <-
           Enum.all?(
             List.delete(@fields, "token"),
             &match?({:ok, _}, Passkeys.decode_base64url(params[&1]))
           ) do
      assertion = Map.take(params, @fields)

      {:noreply,
       socket
       |> assign(:form, to_form(assertion))
       |> assign(:current_token, nil)
       |> assign(:trigger_action, true)
       |> assign(:error, nil)}
    else
      _ -> {:noreply, assign(socket, :error, error_message("invalid_assertion"))}
    end
  end

  def handle_event("passkey_login_error", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, :error, error_message(reason))}
  end

  def handle_event("passkey_login_error", _, socket) do
    {:noreply, assign(socket, :error, error_message("unknown"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="passkey-login" phx-hook="PasskeyLogin">
      <div
        id="passkey-login-controls"
        hidden={!@passkey_supported}
        class="mt-5 border-t border-gray-200 pt-5 dark:border-gray-700"
      >
        <button id="passkey-login-button" type="button" class="btn btn-white w-full">
          Sign in with a passkey
        </button>
        <p
          id="passkey-login-status"
          role="status"
          aria-live="polite"
          class="mt-2 text-sm text-gray-600 dark:text-gray-300"
        >
          {@error}
        </p>
      </div>

      <.form
        for={@form}
        id="passkey-login-form"
        action={~p"/users/passkeys"}
        phx-trigger-action={@trigger_action}
        class="hidden"
      >
        <input :for={field <- @fields} type="hidden" name={field} value={@form[field].value} />
      </.form>
    </div>
    """
  end

  defp empty_assertion, do: Map.new(@fields, &{&1, ""})

  defp secure_token_match?(token, current)
       when is_binary(current) and byte_size(token) == byte_size(current),
       do: Plug.Crypto.secure_compare(token, current)

  defp secure_token_match?(_, _), do: false

  defp error_message("timeout"), do: "Passkey request timed out. Please try again."
  defp error_message("canceled"), do: "Passkey sign-in was canceled. Please try again."

  defp error_message("unsupported"),
    do: "This browser does not support passkeys. You can still use your password."

  defp error_message(_), do: "Could not sign in with passkey. Please try again."
end
