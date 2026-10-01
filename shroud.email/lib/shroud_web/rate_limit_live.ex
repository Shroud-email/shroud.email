defmodule ShroudWeb.RateLimitLive do
  @moduledoc "Rate limits connected LiveView events before their handlers run."
  import Phoenix.Component
  import Phoenix.LiveView
  alias Shroud.RateLimit
  alias ShroudWeb.Plugs.ClientIP

  def on_mount(_mode, _params, _session, socket) do
    if connected?(socket) do
      %{address: peer} = get_connect_info(socket, :peer_data)
      ip = ClientIP.resolve(peer, get_connect_info(socket, :x_headers) || [])
      socket = assign(socket, :rate_limit_ip, ip)

      # Upgrades consume HTTP quota in LiveSocket. Mounts have a separate
      # allowance because a single socket can repeatedly join different views.
      case RateLimit.check(:live_mount, {:ip, ip}) do
        {:allow, _} ->
          {:cont, attach_hook(socket, :rate_limit, :handle_event, &handle_event/3)}

        _ ->
          {:halt,
           socket
           |> put_flash(:error, "Too many requests. Please try again later.")
           |> redirect(to: "/users/log_in")}
      end
    else
      {:cont, socket}
    end
  end

  def handle_event(event, _params, socket) do
    actor =
      case socket.assigns[:current_user] do
        %{id: id} -> {:account, id}
        _ -> {:ip, socket.assigns.rate_limit_ip}
      end

    result =
      [:events | event_policies(event)]
      |> Enum.reduce_while(:ok, fn policy, :ok ->
        case RateLimit.check(policy, actor) do
          {:allow, _} -> {:cont, :ok}
          result -> {:halt, result}
        end
      end)

    case result do
      :ok -> {:cont, socket}
      {:deny, milliseconds} -> reject(socket, Integer.ceil_div(milliseconds, 1000))
      {:error, :unavailable} -> reject(socket, 1)
    end
  end

  defp event_policies("update_email"), do: [:account_email]
  defp event_policies("update_password"), do: [{:security, :password}]

  defp event_policies(event)
       when event in ["add_passkey", "passkey_registered", "remove_passkey"],
       do: [{:security, :passkey}]

  defp event_policies(event)
       when event in ["generate_totp_secret", "enable_totp", "disable_totp"],
       do: [{:security, :second_factor}]

  defp event_policies("lifetime_signup"), do: [{:security, :lifetime}]
  defp event_policies("passkey_options"), do: [:passkey_challenge]
  # All root events consume :events. Add sensitive mutations above when
  # introducing or renaming their handlers; ordinary events use only that cap.
  # Component-targeted events and live patches do not run this root event hook.
  defp event_policies(_event), do: []

  defp reject(socket, seconds) do
    message = "Too many requests. Please try again in #{seconds} seconds."

    socket =
      if socket.view == ShroudWeb.PasskeyLoginLive,
        do: assign(socket, :error, message),
        else: put_flash(socket, :error, message)

    {:halt, %{error: message, retry_after: seconds}, socket}
  end
end
