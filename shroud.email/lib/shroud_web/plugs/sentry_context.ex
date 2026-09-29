defmodule ShroudWeb.Plugs.SentryContext do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{assigns: %{current_user: user}} = conn, _opts) when not is_nil(user) do
    Sentry.Context.set_user_context(%{id: user.id, email: user.email})
    conn
  end

  def call(%Plug.Conn{} = conn, _opts), do: conn
end
