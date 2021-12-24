defmodule ShroudWeb.Components do
  use Phoenix.Component

  def button(assigns) do
    ~H"""
    <button
      phx-click={@phx_click}
      type="button"
      class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
    >
      <span class="-ml-1 mr-2 h-5 w-5">
        <%= render_slot(@inner_block) %>
      </span>
      <%= @text %>
    </button>
    """
  end

  def toggle(assigns) do
    button_class =
      "relative inline-flex flex-shrink-0 h-6 w-11 border-2 border-transparent rounded-full cursor-pointer transition-colors ease-in-out duration-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"

    toggle_class =
      "pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow transform ring-0 transition ease-in-out duration-200"

    assigns =
      if assigns.enabled do
        assigns
        |> assign(:button_class, button_class <> " bg-indigo-600")
        |> assign(:toggle_class, toggle_class <> " translate-x-5")
      else
        assigns
        |> assign(:button_class, button_class <> " bg-gray-200")
        |> assign(:toggle_class, toggle_class <> " translate-x-0")
      end

    ~H"""
    <button
      type="button"
      class={@button_class}
      role="switch"
      aria-checked={@enabled}
      phx-click={@phx_click}
    >
      <span class="sr-only">
        <%= if @enabled, do: "Disable", else: "Enable" %>
      </span>
      <span
        aria-hidden="true"
        class={@toggle_class}
      ></span>
    </button>
    """
  end
end