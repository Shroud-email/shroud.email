defmodule ShroudWeb.UserSettingsLive do
  use ShroudWeb, :live_view

  alias Shroud.{Accounts, Billing, Repo}
  alias Shroud.Accounts.{TOTP, User}

  embed_templates "user_settings_live/*"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: {ShroudWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    user = Repo.reload!(socket.assigns.current_user)
    billing_config = Application.get_env(:shroud, :billing, [])
    price_id = billing_config[:paddle_yearly_price_id]
    client_token = billing_config[:paddle_client_token]

    title =
      case socket.assigns.live_action do
        :account -> "Account settings"
        :security -> "Security settings"
        :appearance -> "Appearance settings"
        :billing -> "Billing settings"
        :lifetime -> "Lifetime signup"
      end

    {:noreply,
     assign(socket,
       current_user: user,
       page_title: title,
       email_form: to_form(Accounts.change_user_email(user)),
       password_form: to_form(Accounts.change_user_password(user)),
       appearance_form: to_form(%{"theme" => to_string(user.theme)}),
       lifetime_form: to_form(%{"lifetime_code" => ""}),
       totp_form: to_form(%{"verification_code" => ""}),
       trigger_password_submit: false,
       totp_secret: nil,
       otp_qr_code: nil,
       totp_backup_codes: nil,
       show_disable_totp: false,
       paddle_price_id: price_id,
       paddle_checkout_available?: configured?(price_id) and configured?(client_token)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.account :if={@live_action == :account} {assigns} />
    <.security :if={@live_action == :security} {assigns} />
    <.appearance :if={@live_action == :appearance} {assigns} />
    <.billing :if={@live_action == :billing} {assigns} />
    <.lifetime :if={@live_action == :lifetime} {assigns} />
    """
  end

  @impl true
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
         |> put_flash(
           :info,
           "A link to confirm your email change has been sent to the new address."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(changeset))}
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

  def handle_event("update_theme", %{"theme" => theme}, socket) do
    case Accounts.update_user_theme(socket.assigns.current_user, %{theme: theme}) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:appearance_form, to_form(%{"theme" => to_string(user.theme)}))
         |> put_flash(:info, "Appearance updated.")
         |> push_event("set-theme", %{theme: to_string(user.theme)})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid theme preference.")}
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
       |> put_flash(:info, "Enabled two-factor authentication.")}
    else
      {:noreply,
       socket
       |> assign(totp_secret: nil, otp_qr_code: nil, current_user: user)
       |> put_flash(:error, "Invalid two-factor authentication code.")}
    end
  end

  def handle_event("show_disable_totp", _params, socket) do
    {:noreply, assign(socket, :show_disable_totp, true)}
  end

  def handle_event("dismiss_backup_codes", _params, socket) do
    {:noreply, assign(socket, :totp_backup_codes, nil)}
  end

  def handle_event("disable_totp", %{"verification_code" => otp}, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    if user.totp_enabled && TOTP.valid_code?(user, user.totp_secret, otp) do
      user = user |> Repo.reload!() |> TOTP.disable_totp!()

      {:noreply,
       socket
       |> assign(current_user: user, show_disable_totp: false, totp_backup_codes: nil)
       |> put_flash(:info, "Disabled two-factor authentication.")}
    else
      {:noreply, put_flash(socket, :error, "Invalid two-factor authentication code.")}
    end
  end

  def handle_event("lifetime_signup", %{"lifetime_code" => code}, socket) do
    case Billing.redeem_lifetime_code(code, socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "You have successfully signed up for lifetime access!")
         |> push_patch(to: ~p"/settings/billing")}

      {:error, :invalid_code} ->
        {:noreply, put_flash(socket, :error, "Invalid code.")}

      {:error, :already_redeemed} ->
        {:noreply, put_flash(socket, :error, "This code has already been redeemed.")}
    end
  end

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

  defp configured?(value), do: is_binary(value) and value != ""
end
