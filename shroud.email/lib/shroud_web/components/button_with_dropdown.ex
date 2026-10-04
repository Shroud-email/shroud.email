defmodule ShroudWeb.Components.ButtonWithDropdown do
  use ShroudWeb, :component
  import ShroudWeb.Components.DropdownMenu

  attr(:text, :string, required: true)
  attr(:icon, :atom, default: nil)
  attr(:intent, :atom, default: :primary)
  attr(:disabled, :boolean, default: false)
  attr(:click, :string, default: nil)

  slot(:inner_block, required: true)

  def button_with_dropdown(assigns) do
    ~H"""
    <div class="inline-flex rounded-button shadow-xs">
      <.button
        click={@click}
        intent={@intent}
        shape={:left}
        class="relative focus:z-10"
      >
        <span :if={@icon} class="-ml-1 mr-2 h-5 w-5">
          <.icon solid name={@icon} />
        </span>
        {@text}
      </.button>
      <.dropdown_menu
        class="-ml-px block"
        intent={@intent}
        button_class="relative focus:z-10"
        disabled={@disabled}
      >
        <:button_content>
          <.icon name={:chevron_down} solid class="h-5 w-5" />
        </:button_content>
        {render_slot(@inner_block)}
      </.dropdown_menu>
    </div>
    """
  end
end
