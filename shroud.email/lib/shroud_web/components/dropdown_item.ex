defmodule ShroudWeb.Components.DropdownItem do
  use ShroudWeb, :component

  attr(:index, :integer, required: true)
  attr(:text, :string, required: true)
  attr(:click, :string, required: false)
  attr(:id, :string, default: nil)
  attr(:disabled, :boolean, default: false)
  attr(:tooltip, :string, default: nil)

  def dropdown_item(assigns) do
    ~H"""
    <.button
      intent={:unstyled}
      id={@id}
      click={if(!@disabled, do: @click)}
      phx-value-text={@text}
      type="button"
      class={[
        "text-left px-4 py-2 text-sm",
        if(@disabled,
          do: "text-gray-400 dark:text-gray-500 cursor-not-allowed",
          else: "text-gray-700 dark:text-gray-300"
        )
      ]}
      aria-disabled={@disabled && "true"}
      aria-label={if(@tooltip, do: "#{@text}: #{@tooltip}")}
      x-tooltip.raw.placement.left={@tooltip}
      x-bind:class={
        if(!@disabled,
          do:
            "{ 'bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-gray-100': activeIndex === #{@index} }"
        )
      }
      role="menuitem"
      tabindex="-1"
      {%{
        "@mouseenter" => if(@disabled, do: "activeIndex = -1", else: "activeIndex = #{@index}"),
        "@mouseleave" => "activeIndex = -1"
      }}
      alpine_click={if(!@disabled, do: "open = false; focusButton()")}
    >
      {@text}
    </.button>
    """
  end
end
