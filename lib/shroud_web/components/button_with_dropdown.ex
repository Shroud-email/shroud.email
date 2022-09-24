defmodule ShroudWeb.Components.ButtonWithDropdown do
  use Surface.Component
  alias ShroudWeb.Components.{DropdownMenu}

  prop text, :string, required: true
  prop icon, :module, required: false
  prop intent, :atom, default: :primary
  prop disabled, :boolean, default: false
  prop click, :event, required: false

  slot default, required: true

  def render(assigns) do
    class =
      case assigns.intent do
        :primary -> "border-indigo-400 text-white bg-indigo-600 hover:bg-indigo-700"
        :secondary -> "text-indigo-700 bg-indigo-100 hover:bg-indigo-200"
        :white -> "border-gray-300 text-gray-700 bg-white hover:bg-gray-50"
      end

    ~F"""
    <div class="inline-flex rounded-md shadow-sm">
      <button
        :on-click={@click}
        type="button"
        class={class <>
          " relative inline-flex items-center rounded-l-md border px-4 py-2 text-sm font-medium focus:z-10 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"}
      >
        <span :if={@icon} class="-ml-1 mr-2 h-5 w-5">
          <Component module={@icon} />
        </span>
        {@text}
      </button>
      <DropdownMenu
        class="-ml-px block"
        button_class={class <>
          " relative inline-flex items-center rounded-r-md border px-2 py-2 text-sm font-medium focus:z-10 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"}
        disabled={@disabled}
      >
        <:button_content>
          <Heroicons.Solid.ChevronDownIcon class="h-5 w-5" />
        </:button_content>
        <#slot />
      </DropdownMenu>
    </div>
    """
  end
end
