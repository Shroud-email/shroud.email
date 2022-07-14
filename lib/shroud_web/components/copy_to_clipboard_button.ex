defmodule ShroudWeb.Components.CopyToClipboardButton do
  use Surface.Component

  prop text, :string, required: true
  prop class, :css_class, required: false

  def render(assigns) do
    alpine_copy_function = """
      navigator.clipboard.writeText('#{assigns.text}');
      tooltip = 'Copied!';
      setTimeout(() => tooltip = 'Copy to clipboard', 1500);
    """

    ~F"""
    <div x-data="{ tooltip: 'Copy to clipboard' }" class={@class}>
      <button
        x-tooltip="tooltip"
        type="button"
        class="rounded p-1 focus:ring focus:ring-indigo-500"
        @click={alpine_copy_function}
      >
        <Heroicons.Solid.ClipboardCopyIcon class="h-5 w-5" />
      </button>
    </div>
    """
  end
end
