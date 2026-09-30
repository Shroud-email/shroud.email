defmodule ShroudWeb.Components.CopyToClipboardButton do
  use ShroudWeb, :component

  attr(:id, :string, required: true)
  attr(:text, :string, required: true)
  attr(:class, :string, default: nil)

  def copy_to_clipboard_button(assigns) do
    ~H"""
    <div class={@class}>
      <button
        id={@id}
        phx-hook="CopyToClipboard"
        type="button"
        aria-label={"Copy #{@text} to clipboard"}
        class="flex items-center justify-center rounded p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 focus:ring focus:ring-indigo-500"
        data-clipboard-text={@text}
      >
        <.icon name={:clipboard_document} class="h-4 w-4" />
      </button>
    </div>
    """
  end
end
