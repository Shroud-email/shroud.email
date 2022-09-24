defmodule ShroudWeb.UserLiveAuth do
  import Phoenix.LiveView
  alias Shroud.Accounts

  # See https://hexdocs.pm/phoenix_live_view/security-model.html#mounting-considerations

  def on_mount(:default, _params, %{"user_token" => user_token} = _session, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    if socket.assigns.current_user do
      Sentry.Context.set_user_context(%{
        id: socket.assigns.current_user.id,
        email: socket.assigns.current_user.email
      })
    end

    if socket.assigns.current_user && socket.assigns.current_user.confirmed_at do
      {:cont, socket}
    else
      {:halt, redirect_require_login(socket)}
    end
  end

  defp redirect_require_login(socket) do
    socket
    |> put_flash(:error, "Please sign in")
    |> redirect(to: "/users/log_in")
  end
end
