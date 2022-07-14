defmodule ShroudWeb.Components.Toggle do
  use Surface.Component

  prop on, :boolean, required: true
  prop click, :event, required: true

  def render(assigns) do
    button_class =
      "relative inline-flex flex-shrink-0 h-6 w-11 border-2 border-transparent rounded-full cursor-pointer transition-colors ease-in-out duration-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"

    toggle_class =
      "pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow transform ring-0 transition ease-in-out duration-200"

    [button_class, toggle_class] =
      if assigns.on do
        [button_class <> " bg-indigo-600", toggle_class <> " translate-x-5"]
      else
        [button_class <> " bg-gray-200", toggle_class <> " translate-x-0"]
      end

    sr_text = if assigns.on, do: "Disable", else: "Enable"

    ~F"""
    <button type="button" class={button_class} role="switch" aria-checked={@on} :on-click={@click}>
      <span class="sr-only">
        {sr_text}
      </span>
      <span aria-hidden="true" class={toggle_class} />
    </button>
    """
  end
end
