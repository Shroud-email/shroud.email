defmodule ShroudWeb.Components.DropdownMenu do
  use ShroudWeb, :component

  attr(:class, :string, default: "")
  attr(:button_class, :string, default: "")
  attr(:disabled, :boolean, default: false)
  slot(:inner_block, required: true)
  slot(:button_content, required: true)

  def dropdown_menu(assigns) do
    ~H"""
    <div
      class={@class <> " relative"}
      x-data="AlpineComponents.menu({ open: false })"
      x-init="init()"
      @keydown.escape.stop="open = false; focusButton()"
      @click.away="onClickAway($event)"
    >
      <div>
        <button
          type="button"
          disabled={@disabled}
          class={@button_class}
          x-id="['button']"
          aria-haspopup="true"
          x-ref="button"
          @click="onButtonClick()"
          x-bind:aria-expanded="open.toString()"
          @keydown.arrow-up.prevent="onArrowUp()"
          @keydown.arrow-down.prevent="onArrowDown()"
        >
          <span class="sr-only">Open menu</span>
          <%= render_slot(@button_content) %>
        </button>
      </div>

      <div
        x-show="open"
        x-transition:enter="transition ease-out duration-100"
        x-transition:enter-start="transform opacity-0 scale-95"
        x-transition:enter-end="transform opacity-100 scale-100"
        x-transition:leave="transition ease-in duration-75"
        x-transition:leave-start="transform opacity-100 scale-100"
        x-transition:leave-end="transform opacity-0 scale-95"
        class="origin-top-right absolute right-0 z-10 flex flex-col mt-2 w-48 rounded-md shadow-lg py-1 bg-white ring-1 ring-black ring-opacity-5 focus:outline-none"
        x-ref="menu-items"
        x-bind:aria-activedescendant="activeDescendant"
        role="menu"
        aria-orientation="vertical"
        x-bind:aria-labelledby="$id('button')"
        tabindex="-1"
        @keydown.arrow-up.prevent="onArrowUp()"
        @keydown.arrow-down.prevent="onArrowDown()"
        @keydown.tab="open = false"
        @keydown.enter.prevent="open = false; focusButton()"
        @keyup.space.prevent="open = false; focusButton()"
        style="display: none;"
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end
