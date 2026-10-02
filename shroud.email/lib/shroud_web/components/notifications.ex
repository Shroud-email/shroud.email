defmodule ShroudWeb.Components.Notifications do
  @moduledoc "Shared notification presentation and timing for the application's layouts."
  use Phoenix.Component

  import ShroudWeb.Components.Atoms, only: [icon: 1]

  # Keep Phoenix's redirect transport, while giving in-place messages unique toast IDs.
  def put_notification(socket, kind, message) do
    LiveToast.put_toast(socket, kind, message, duration: if(kind == :error, do: 0, else: 8000))
  end

  attr :flash, :map, required: true
  attr :socket, :any, default: nil
  attr :toasts_sync, :any, default: nil
  attr :persistent, :boolean, default: false

  def notification_group(assigns) do
    assigns = assign(assigns, :notifications, notifications(assigns.flash, assigns.toasts_sync))

    ~H"""
    <%= if @socket && !@persistent do %>
      {Phoenix.Component.live_render(@socket, ShroudWeb.NotificationsLive,
        id: "notifications",
        sticky: true
      )}
      <div id="notification-source" phx-hook="NotificationSource" hidden>
        <div
          :for={notification <- @notifications}
          data-id={notification.id}
          data-kind={notification.kind}
          data-duration={notification.duration}
        >
          {notification.message}
        </div>
      </div>
    <% else %>
      <LiveToast.toast_group
        flash={@flash}
        connected={@socket != nil}
        toasts_sync={@toasts_sync}
        kinds={[:success, :info, :error]}
        corner={:top_right}
        connection_notifications={false}
        group_class_fn={&group_class/1}
        toast_class_fn={&toast_class/1}
        toast_component_fn={&content/1}
      />
    <% end %>
    """
  end

  defp notifications(flash, sync) do
    for {kind, message} <- flash, message && kind in ~w(info success error) do
      toast = Enum.find(sync || [], &(to_string(&1.kind) == kind && &1.msg == message))

      %{
        id: if(toast, do: toast.uuid, else: "flash-#{kind}-#{message}"),
        kind: kind,
        message: message,
        duration: if(toast, do: toast.duration, else: if(kind == "error", do: 0, else: 8000))
      }
    end
  end

  def group_class(_assigns) do
    "fixed z-50 max-h-screen w-full max-w-[420px] p-4 sm:p-6 pointer-events-none grid origin-center bottom-0 left-1/2 -translate-x-1/2 items-end sm:bottom-auto sm:top-0 sm:left-auto sm:right-0 sm:translate-x-0 sm:items-start"
  end

  def toast_class(assigns) do
    [
      "group/toast z-[100] pointer-events-auto relative w-full items-center justify-between gap-3 origin-center overflow-hidden rounded-lg p-4 shadow-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 col-start-1 col-end-1 row-start-1 row-end-2",
      "[&>button]:text-gray-500 dark:[&>button]:text-gray-400 [&>button_svg]:opacity-100 [&>button:hover]:text-gray-900 dark:[&>button:hover]:text-gray-100 [&>button:focus-visible]:ring-2 [&>button:focus-visible]:ring-indigo-500",
      "[@media(scripting:enabled)]:opacity-0 [@media(scripting:enabled)]:[[data-phx-main]_&]:opacity-100",
      if(assigns[:rest][:hidden], do: "hidden", else: "flex")
    ]
  end

  def content(assigns) do
    {name, class} =
      case assigns.kind do
        :success -> {:check_circle, "text-green-500 dark:text-green-400"}
        :error -> {:exclamation_circle, "text-red-500 dark:text-red-400"}
        :info -> {:information_circle, "text-gray-400"}
      end

    assigns = assign(assigns, icon: name, icon_class: class)

    ~H"""
    <div class="flex items-start gap-3 min-w-0 grow">
      <.icon name={@icon} class={"h-6 w-6 shrink-0 " <> @icon_class} />
      <p class="text-sm font-medium pt-0.5 break-words min-w-0">{@body}</p>
    </div>
    """
  end
end
