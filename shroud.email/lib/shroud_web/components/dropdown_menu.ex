defmodule ShroudWeb.Components.DropdownMenu do
  use ShroudWeb, :component

  attr(:class, :string, default: "")
  attr(:button_class, :string, default: "")
  attr(:intent, :atom, default: :primary)
  attr(:disabled, :boolean, default: false)
  attr(:id, :string, default: nil)
  attr(:label, :string, default: "Open menu")
  attr(:tooltip, :string, default: nil)
  attr(:shape, :atom, default: :right, values: [:default, :left, :right, :top_right])
  attr(:align, :atom, default: :right, values: [:left, :right])
  slot(:inner_block, required: true)
  slot(:button_content, required: true)

  def dropdown_menu(assigns) do
    ~H"""
    <div
      class={@class <> " relative"}
      x-data="AlpineComponents.menu({ open: false })"
      x-init="init()"
      x-id="['button']"
      x-on:keydown.capture="instant = true"
      x-on:pointerdown.capture="instant = false"
      @keydown.escape.stop="open = false; focusButton()"
      @click.away="onClickAway($event)"
    >
      <div>
        <.button
          intent={@intent}
          id={@id}
          aria-label={@label}
          x-tooltip.raw={@tooltip}
          shape={@shape}
          size={:icon}
          disabled={@disabled}
          class={@button_class}
          x-bind:id={if(!@id, do: "$id('button')")}
          aria-haspopup="true"
          x-ref="button"
          alpine_click="onButtonClick()"
          x-bind:aria-expanded="open.toString()"
          x-on:keydown.arrow-up.prevent="onArrowUp(); $nextTick(() => $refs['menu-items'].focus())"
          x-on:keydown.arrow-down.prevent="onArrowDown(); $nextTick(() => $refs['menu-items'].focus())"
        >
          {render_slot(@button_content)}
        </.button>
      </div>

      <div
        x-show="open"
        x-transition:enter="menu-enter"
        x-transition:enter-start="menu-closed"
        x-transition:enter-end="menu-open"
        x-transition:leave="menu-leave"
        x-transition:leave-start="menu-open"
        x-transition:leave-end="menu-closed"
        x-bind:class="{ 'menu-instant': instant }"
        class={[
          "menu-motion absolute z-10 flex flex-col mt-2 w-48 rounded-md shadow-lg py-1 bg-white dark:bg-gray-800 ring-1 ring-black/5 dark:ring-gray-700 focus:outline-hidden",
          if(@align == :left, do: "left-0 origin-top-left", else: "right-0 origin-top-right")
        ]}
        x-ref="menu-items"
        x-bind:aria-activedescendant="activeDescendant"
        role="menu"
        aria-orientation="vertical"
        aria-labelledby={@id}
        x-bind:aria-labelledby={if(!@id, do: "$id('button')")}
        tabindex="-1"
        @keydown.arrow-up.prevent="onArrowUp()"
        @keydown.arrow-down.prevent="onArrowDown()"
        @keydown.tab="open = false"
        @keydown.enter.prevent="if (activeIndex >= 0) items[activeIndex]?.click(); open = false; focusButton()"
        @keyup.space.prevent="if (activeIndex >= 0) items[activeIndex]?.click(); open = false; focusButton()"
        style="display: none;"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
