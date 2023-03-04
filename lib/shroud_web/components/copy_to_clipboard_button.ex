defmodule ShroudWeb.Components.CopyToClipboardButton do
  use ShroudWeb, :component

  attr(:text, :string, required: true)
  attr(:class, :string, required: false)

  def copy_to_clipboard_button(assigns) do
    assigns =
      assigns
      |> assign(:alpine_copy_function, """
        navigator.clipboard.writeText('#{assigns.text}');
        tooltip = 'Copied!';
        setTimeout(() => tooltip = 'Copy to clipboard', 1500);
      """)

    ~H"""
    <div x-data="{ tooltip: 'Copy to clipboard' }" class={@class}>
      <button
        x-tooltip="tooltip"
        type="button"
        class="rounded p-1 focus:ring focus:ring-indigo-500"
        x-on:click={@alpine_copy_function}
      >
        <.icon name={:clipboard_document} solid class="h-5 w-5" />
      </button>
    </div>
    """
  end
end
