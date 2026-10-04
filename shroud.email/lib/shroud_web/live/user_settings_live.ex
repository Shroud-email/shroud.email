defmodule ShroudWeb.UserSettingsLive do
  use ShroudWeb, :live_view

  alias Shroud.{Accounts, Billing, Mcp, Repo}
  alias Shroud.Accounts.{Passkeys, TOTP, User}
  alias ShroudWeb.Components.PopupAlert

  embed_templates "user_settings_live/*"

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      assign(socket,
        email_form: to_form(Accounts.change_user_email(user)),
        password_form: to_form(Accounts.change_user_password(user)),
        lifetime_form: to_form(%{"lifetime_code" => ""}),
        totp_form: to_form(%{"verification_code" => ""}),
        trigger_password_submit: false,
        totp_secret: nil,
        otp_qr_code: nil,
        totp_backup_codes: nil,
        show_disable_totp: false,
        passkey_form: to_form(%{"current_password" => ""}, as: :passkey),
        passkey_dialog: nil,
        passkey_password_error: nil,
        passkey_supported: false,
        passkey_token: nil,
        passkey_pending: false,
        passkey_status: nil,
        passkey_error: false,
        connections_empty?: true
      )
      |> stream(:passkeys, [])
      |> stream(:connections, [])

    {:ok, socket, layout: {ShroudWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    socket =
      if socket.assigns.live_action == :security,
        do: stream(socket, :passkeys, Accounts.list_passkeys(user), reset: true),
        else: socket |> cancel_passkey() |> assign(:passkey_dialog, nil)

    socket =
      cond do
        socket.assigns.live_action != :connections -> socket
        Mcp.enabled?(user) -> load_connections(socket)
        true -> push_navigate(socket, to: ~p"/settings/security")
      end

    billing_config = Application.get_env(:shroud, :billing, [])
    price_id = billing_config[:paddle_yearly_price_id]
    client_token = billing_config[:paddle_client_token]

    titles = %{
      account: "Account settings",
      security: "Security settings",
      connections: "Connected apps",
      appearance: "Appearance settings",
      billing: "Billing settings",
      lifetime: "Lifetime signup"
    }

    {:noreply,
     assign(socket,
       current_user: user,
       page_title: titles[socket.assigns.live_action],
       email_preferences_enabled?: Accounts.email_preferences_enabled?(user),
       email_preferences_form: to_form(User.email_preferences_changeset(user, %{})),
       appearance_form: to_form(%{"theme" => to_string(user.theme)}),
       totp_backup_codes:
         if(socket.assigns.live_action == :security, do: socket.assigns.totp_backup_codes),
       paddle_price_id: price_id,
       paddle_checkout_available?: configured?(price_id) and configured?(client_token)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.account :if={@live_action == :account} {assigns} />
    <.security :if={@live_action == :security} {assigns} />
    <.connections :if={@live_action == :connections} {assigns} />
    <.appearance :if={@live_action == :appearance} {assigns} />
    <.billing :if={@live_action == :billing} {assigns} />
    <.lifetime :if={@live_action == :lifetime} {assigns} />
    """
  end

  @impl true
  def handle_event("revoke_connection", %{"id" => id}, socket) do
    with true <- Mcp.enabled?(socket.assigns.current_user),
         {id, ""} <- Integer.parse(id),
         true <- Mcp.revoke(socket.assigns.current_user, id) do
      {:noreply,
       socket
       |> load_connections()
       |> put_notification(:info, "App disconnected.")}
    else
      _ -> {:noreply, put_notification(socket, :error, "Connection not found.")}
    end
  end

  def handle_event("update_email", %{"current_password" => password, "user" => params}, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    case Accounts.apply_user_email(user, password, params) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/settings/confirm_email/#{&1}")
        )

        {:noreply,
         socket
         |> assign(:email_form, to_form(Accounts.change_user_email(user)))
         |> put_notification(
           :info,
           "A link to confirm your email change has been sent to the new address."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(changeset))}
    end
  end

  def handle_event("update_email_preferences", %{"user" => params}, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    case Accounts.update_user_email_preferences(user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(
           current_user: user,
           email_preferences_form: to_form(User.email_preferences_changeset(user, %{}))
         )
         |> put_notification(:info, "Email preferences updated.")}

      {:error, :feature_disabled} ->
        {:noreply,
         socket
         |> assign(:email_preferences_enabled?, false)
         |> put_notification(:error, "Email preferences are not available.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_preferences_form, to_form(changeset))}
    end
  end

  def handle_event("update_password", %{"current_password" => password, "user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Repo.reload!()
      |> Accounts.change_user_password(params)
      |> User.validate_current_password(password)
      |> Map.put(:action, :update)

    {:noreply,
     assign(socket,
       password_form: to_form(changeset),
       trigger_password_submit: changeset.valid?
     )}
  end

  def handle_event("passkey_supported", %{"supported" => supported}, socket) do
    {:noreply, assign(socket, :passkey_supported, supported == true)}
  end

  def handle_event("open_passkey_dialog", %{"action" => "add"}, socket) do
    {:noreply, open_passkey_dialog(socket, %{action: :add})}
  end

  def handle_event("open_passkey_dialog", %{"action" => "remove", "id" => id}, socket) do
    credential =
      socket.assigns.current_user
      |> Accounts.list_passkeys()
      |> Enum.find(&(to_string(&1.id) == id))

    if credential do
      {:noreply, open_passkey_dialog(socket, %{action: :remove, credential: credential})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_passkey", params, socket) do
    user = Repo.reload!(socket.assigns.current_user)
    password = passkey_password(params)
    socket = socket |> cancel_passkey() |> assign(:passkey_password_error, nil)

    cond do
      user.confirmed_at && User.valid_password?(user, password) ->
        {:ok, options} = Passkeys.begin_registration(user)

        {:noreply,
         socket
         |> assign(
           passkey_token: options.token,
           passkey_pending: true,
           passkey_status: "Preparing your passkey…",
           passkey_error: false
         )
         |> push_event("passkey-register", %{
           token: Base.url_encode64(options.token, padding: false),
           publicKey: %{
             challenge: options.challenge,
             rp: %{id: options.rp_id, name: "Shroud.email"},
             user: %{id: options.user_handle, name: user.email, displayName: user.email},
             pubKeyCredParams: [%{type: "public-key", alg: -7}, %{type: "public-key", alg: -257}],
             authenticatorSelection: %{residentKey: "required", userVerification: "required"},
             excludeCredentials:
               Enum.map(options.exclude_credentials, &%{type: "public-key", id: &1}),
             attestation: "none",
             timeout: 300_000
           }
         })}

      is_nil(user.confirmed_at) ->
        {:noreply, passkey_failure(socket, "Could not authorize passkey registration.")}

      true ->
        {:noreply,
         socket
         |> passkey_failure(nil)
         |> assign(:passkey_password_error, "Incorrect password. Please try again.")}
    end
  end

  def handle_event("passkey_registered", params, socket) do
    user = Repo.reload!(socket.assigns.current_user)
    token = socket.assigns.passkey_token

    result =
      with true <- user.confirmed_at != nil,
           true <- authorized_passkey_token?(socket, params["token"]),
           {:ok, attestation} <- Passkeys.decode_base64url(params["attestationObject"]),
           {:ok, client_data} <- Passkeys.decode_base64url(params["clientDataJSON"]),
           {:ok, raw_id} <- Passkeys.decode_base64url(params["rawId"]) do
        Passkeys.register(user, token, attestation, client_data, "Passkey", raw_id)
      else
        _ -> {:error, :invalid_registration}
      end

    case result do
      {:ok, credential} ->
        {:reply, %{},
         socket
         |> assign(
           passkey_token: nil,
           passkey_pending: false,
           passkey_dialog: nil,
           passkey_status: "Passkey added."
         )
         |> stream_insert(:passkeys, credential)}

      _ ->
        {:reply, %{error: "invalid_registration"},
         passkey_failure(socket, "Could not add passkey. Please try again.")}
    end
  end

  def handle_event("passkey_status", %{"token" => token, "phase" => phase}, socket) do
    if authorized_passkey_token?(socket, token) && socket.assigns.passkey_pending do
      message =
        case phase do
          "waiting" -> "Waiting for your passkey…"
          "saving" -> "Saving your passkey…"
          _ -> socket.assigns.passkey_status
        end

      {:noreply, assign(socket, :passkey_status, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("passkey_error", %{"token" => token, "reason" => reason}, socket) do
    if authorized_passkey_token?(socket, token) && socket.assigns.passkey_pending do
      message =
        case reason do
          "timeout" ->
            "Passkey request timed out. Please try again."

          "canceled" ->
            "Passkey creation was canceled. Please try again."

          "unsupported" ->
            "This browser does not support passkeys. You can still use your password."

          _ ->
            "Could not add passkey. Please try again."
        end

      {:noreply, passkey_failure(socket, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_passkey", params, socket) do
    user = Repo.reload!(socket.assigns.current_user)
    credentials = Accounts.list_passkeys(user)

    with {:ok, id} <- Passkeys.decode_base64url(params["credential_id"]),
         credential when not is_nil(credential) <-
           Enum.find(credentials, &(&1.credential_id == id)) do
      cond do
        is_nil(user.confirmed_at) ->
          {:noreply, assign(socket, :passkey_password_error, "Could not remove passkey.")}

        not User.valid_password?(user, passkey_password(params)) ->
          {:noreply,
           assign(socket, :passkey_password_error, "Incorrect password. Please try again.")}

        true ->
          Accounts.remove_passkey(user, id)

          {:noreply,
           socket
           |> assign(passkey_dialog: nil, passkey_password_error: nil)
           |> stream(:passkeys, Accounts.list_passkeys(user), reset: true)
           |> put_notification(:info, "Passkey removed.")}
      end
    else
      _ -> {:noreply, stream(socket, :passkeys, credentials, reset: true)}
    end
  end

  def handle_event("update_theme", %{"theme" => theme}, socket) do
    case Accounts.update_user_theme(socket.assigns.current_user, %{theme: theme}) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:appearance_form, to_form(%{"theme" => to_string(user.theme)}))
         |> put_notification(:info, "Appearance updated.")
         |> push_event("set-theme", %{theme: to_string(user.theme)})}

      {:error, _changeset} ->
        {:noreply, put_notification(socket, :error, "Invalid theme preference.")}
    end
  end

  def handle_event("generate_totp_secret", _params, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    if user.totp_enabled do
      {:noreply, assign(socket, :current_user, user)}
    else
      secret = TOTP.create_secret()
      qr_code = user |> TOTP.otp_uri(secret) |> EQRCode.encode() |> EQRCode.svg(width: 264)
      {:noreply, assign(socket, totp_secret: secret, otp_qr_code: qr_code)}
    end
  end

  def handle_event("enable_totp", %{"verification_code" => otp}, socket) do
    user = Repo.reload!(socket.assigns.current_user)
    secret = socket.assigns.totp_secret

    if !user.totp_enabled && secret && TOTP.valid_code?(user, secret, otp) do
      backup_codes = TOTP.enable_totp!(user, secret)

      {:noreply,
       socket
       |> assign(
         current_user: Repo.reload!(user),
         totp_secret: nil,
         otp_qr_code: nil,
         totp_backup_codes: backup_codes
       )
       |> put_notification(:info, "Enabled two-factor authentication.")}
    else
      {:noreply,
       socket
       |> assign(totp_secret: nil, otp_qr_code: nil, current_user: user)
       |> put_notification(:error, "Invalid two-factor authentication code.")}
    end
  end

  def handle_event("show_disable_totp", _params, socket) do
    {:noreply, assign(socket, :show_disable_totp, true)}
  end

  def handle_event("dismiss_backup_codes", _params, socket) do
    {:noreply, assign(socket, :totp_backup_codes, nil)}
  end

  def handle_event("backup_copy_failed", _params, socket) do
    PopupAlert.show("backup-copy-error")
    {:noreply, socket}
  end

  def handle_event("disable_totp", %{"verification_code" => otp}, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    if user.totp_enabled && TOTP.valid_code?(user, user.totp_secret, otp) do
      user = user |> Repo.reload!() |> TOTP.disable_totp!()

      {:noreply,
       socket
       |> assign(current_user: user, show_disable_totp: false, totp_backup_codes: nil)
       |> put_notification(:info, "Disabled two-factor authentication.")}
    else
      {:noreply, put_notification(socket, :error, "Invalid two-factor authentication code.")}
    end
  end

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

  @impl true
  def handle_info(:passkey_dialog_closed, socket) do
    {:noreply,
     socket
     |> cancel_passkey()
     |> assign(
       passkey_dialog: nil,
       passkey_password_error: nil,
       passkey_status: nil,
       passkey_error: false
     )
     |> push_event("passkey-cancel", %{})}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :rest, :global, include: ~w(required minlength maxlength inputmode autocomplete pattern)

  defp input(assigns) do
    ~H"""
    <label for={@id || @field.id} class="block text-sm font-medium text-gray-700 dark:text-gray-300">
      {@label}
    </label>
    <input
      type={@type}
      id={@id || @field.id}
      name={@name || @field.name}
      value={if @type != "password", do: @field.value}
      class="mt-1 block w-full border border-gray-300 rounded-md shadow-xs py-2 px-3 focus:outline-hidden focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400"
      {@rest}
    />
    <span :for={error <- @field.errors} class="invalid-feedback">{translate_error(error)}</span>
    """
  end

  defp load_connections(socket) do
    connections = Mcp.list_connections(socket.assigns.current_user)

    socket
    |> assign(:connections_empty?, connections == [])
    |> stream(:connections, connections, reset: true)
  end

  defp configured?(value), do: is_binary(value) and value != ""

  defp passkey_password(%{"passkey" => %{"current_password" => password}})
       when is_binary(password) and byte_size(password) in 1..72,
       do: password

  defp passkey_password(_), do: nil

  defp open_passkey_dialog(socket, dialog) do
    socket
    |> cancel_passkey()
    |> assign(
      passkey_dialog: dialog,
      passkey_password_error: nil,
      passkey_status: nil,
      passkey_error: false,
      passkey_form: to_form(%{"current_password" => ""}, as: :passkey)
    )
  end

  defp authorized_passkey_token?(socket, encoded) do
    with token when is_binary(token) <- socket.assigns.passkey_token,
         {:ok, supplied} <- Passkeys.decode_base64url(encoded) do
      Plug.Crypto.secure_compare(token, supplied)
    else
      _ -> false
    end
  end

  defp cancel_passkey(socket) do
    if token = socket.assigns.passkey_token do
      Passkeys.consume_challenge(token, :registration, socket.assigns.current_user)
    end

    assign(socket, passkey_token: nil, passkey_pending: false)
  end

  defp passkey_failure(socket, message) do
    socket
    |> cancel_passkey()
    |> assign(passkey_status: message, passkey_error: true)
  end
end
