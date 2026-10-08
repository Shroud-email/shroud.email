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
        class="copy-feedback-button"
        aria-label={"Copy #{@text} to clipboard"}
        size={:compact}
        data-clipboard-text={@text}
      >
        <span
          id={@id <> "-feedback"}
          phx-update="ignore"
          data-copy-feedback
          class="copy-feedback relative inline-flex h-4 w-4 overflow-hidden"
        >
          <.icon name={:clipboard_document} class="copy-feedback-clipboard h-4 w-4" />
          <.icon name={:check} class="copy-feedback-check absolute inset-0 h-4 w-4" />
          <span data-copy-status class="sr-only" role="status" aria-atomic="true"></span>
        </span>
      </.button>
    </div>
    """
  end
end
