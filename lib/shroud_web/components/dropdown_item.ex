defmodule ShroudWeb.Components.DropdownItem do
  use ShroudWeb, :component

  attr(:index, :integer, required: true)
  attr(:text, :string, required: true)
  attr(:click, :string, required: false)

  def dropdown_item(assigns) do
    ~H"""
    <button
      phx-click={@click}
      phx-value-text={@text}
      type="button"
      class="text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-300"
      x-bind:class={"{ 'bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-gray-100': activeIndex === #{@index} }"}
      role="menuitem"
      tabindex="-1"
      @mouseenter={"activeIndex = #{@index}"}
      @mouseleave="activeIndex = -1"
      @click="open = false; focusButton()"
    >
      {@text}
    </button>
    """
  end
end
