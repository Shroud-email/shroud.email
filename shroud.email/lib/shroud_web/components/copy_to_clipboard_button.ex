defmodule ShroudWeb.Components.CopyToClipboardButton do
  use ShroudWeb, :component

  attr(:id, :string, required: true)
  attr(:text, :string, required: true)
  attr(:class, :string, default: nil)

  def copy_to_clipboard_button(assigns) do
    ~H"""
    <div class={@class}>
      <.button
        id={@id}
        phx-hook="CopyToClipboard"
        intent={:text}
        aria-label={"Copy #{@text} to clipboard"}
        size={:compact}
        data-clipboard-text={@text}
      >
        <.icon name={:clipboard_document} class="h-4 w-4" />
      </.button>
    </div>
    """
  end
end
