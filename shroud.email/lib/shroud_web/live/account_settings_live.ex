defmodule ShroudWeb.AccountSettingsLive do
  use ShroudWeb, :live_view

  alias Shroud.{Accounts, Repo}
  alias Shroud.Accounts.User

  import ShroudWeb.SettingsComponents, only: [input: 1]

  embed_templates "account_settings_live/*"

  @impl true
  def mount(_params, _session, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    {:ok,
     assign(socket,
       current_user: user,
       page_title: "Account settings",
       email_form: to_form(Accounts.change_user_email(user)),
       email_preferences_enabled?: Accounts.email_preferences_enabled?(user),
       email_preferences_form: to_form(User.email_preferences_changeset(user, %{}))
     ), layout: {ShroudWeb.Layouts, :settings}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.account {assigns} />
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
end
