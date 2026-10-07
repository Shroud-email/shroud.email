defmodule ShroudWeb.AppearanceSettingsLive do
  use ShroudWeb, :live_view

  alias Shroud.{Accounts, Repo}

  embed_templates "appearance_settings_live/*"

  @impl true
  def mount(_params, _session, socket) do
    user = Repo.reload!(socket.assigns.current_user)

    {:ok,
     assign(socket,
       current_user: user,
       page_title: "Appearance settings",
       appearance_form: to_form(%{"theme" => to_string(user.theme)})
     ), layout: {ShroudWeb.Layouts, :settings}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.appearance {assigns} />
    """
  end

  @impl true
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
end
