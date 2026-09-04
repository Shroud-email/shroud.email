defmodule ShroudWeb.Components.CopyToClipboardButton do
  use ShroudWeb, :component

  attr(:id, :string, default: nil)
  attr(:text, :string, required: true)
  attr(:class, :string, default: nil)

  def copy_to_clipboard_button(assigns) do
    ~H"""
    <div x-data="{ tooltip: 'Copy to clipboard' }" class={@class}>
      <button
        id={@id}
        x-tooltip="tooltip"
        type="button"
        aria-label={"Copy #{@text} to clipboard"}
        class="rounded p-1 focus:ring focus:ring-indigo-500"
        data-clipboard-text={@text}
        x-on:click="
          navigator.clipboard.writeText($el.dataset.clipboardText);
          tooltip = 'Copied!';
          setTimeout(() => tooltip = 'Copy to clipboard', 1500);
        "
      >
        <.icon name={:clipboard_document} solid class="h-5 w-5" />
      </button>
    </div>
    """
  end
end
