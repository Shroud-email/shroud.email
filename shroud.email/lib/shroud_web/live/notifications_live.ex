defmodule ShroudWeb.NotificationsLive do
  @moduledoc "Notification stack retained across navigation within a LiveView session."
  use Phoenix.LiveView, layout: false

  import ShroudWeb.Components.Notifications

  @impl true
  def render(assigns) do
    ~H"""
    <.notification_group flash={%{}} socket={@socket} persistent />
    """
  end
end
