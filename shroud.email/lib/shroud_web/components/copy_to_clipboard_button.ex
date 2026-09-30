defmodule ShroudWeb.Components.CopyToClipboardButton do
  use ShroudWeb, :component

  attr(:id, :string, default: nil)
  attr(:text, :string, required: true)
  attr(:class, :string, default: nil)

  def copy_to_clipboard_button(assigns) do
    ~H"""
    <div x-data="{ tooltip: 'Copy to clipboard', resetTimer: null }" class={@class}>
      <button
        id={@id}
        x-tooltip="{ content: tooltip, hideOnClick: false }"
        type="button"
        aria-label={"Copy #{@text} to clipboard"}
        class="flex items-center justify-center rounded p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 focus:ring focus:ring-indigo-500"
        data-clipboard-text={@text}
        x-on:click="
          clearTimeout(resetTimer);
          await navigator.clipboard.writeText($el.dataset.clipboardText);
          tooltip = 'Copied!';
          resetTimer = setTimeout(() => tooltip = 'Copy to clipboard', 2000);
        "
      >
        <.icon name={:clipboard_document} class="h-4 w-4" />
      </button>
    </div>
    """
  end
end
