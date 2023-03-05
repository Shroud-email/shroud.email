defmodule ShroudWeb.Components.ButtonWithDropdown do
  use ShroudWeb, :component
  import ShroudWeb.Components.DropdownMenu

  attr(:text, :string, required: true)
  attr(:icon, :atom, required: false)
  attr(:intent, :atom, default: :primary)
  attr(:disabled, :boolean, default: false)
  attr(:click, :string, required: false)

  slot(:inner_block, required: true)

  def button_with_dropdown(assigns) do
    class =
      case assigns.intent do
        :primary -> "border-indigo-400 text-white bg-indigo-600 hover:bg-indigo-700"
        :secondary -> "text-indigo-700 bg-indigo-100 hover:bg-indigo-200"
        :white -> "border-gray-300 text-gray-700 bg-white hover:bg-gray-50"
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <div class="inline-flex rounded-md shadow-sm">
      <button
        phx-click={@click}
        type="button"
        class={@class <>
          " relative inline-flex items-center rounded-l-md border px-4 py-2 text-sm font-medium focus:z-10 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"}
      >
        <span :if={@icon} class="-ml-1 mr-2 h-5 w-5">
          <.icon solid name={@icon} />
        </span>
        <%= @text %>
      </button>
      <.dropdown_menu
        class="-ml-px block"
        button_class={@class <>
          " relative inline-flex items-center rounded-r-md border px-2 py-2 text-sm font-medium focus:z-10 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"}
        disabled={@disabled}
      >
        <:button_content>
          <.icon name={:chevron_down} solid class="h-5 w-5" />
        </:button_content>
        <%= render_slot(@inner_block) %>
      </.dropdown_menu>
    </div>
    """
  end
end
