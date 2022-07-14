defmodule ShroudWeb.Components.Button do
  use Surface.Component

  prop text, :string, required: true
  prop icon, :module, required: false
  prop click, :event, required: true

  def render(assigns) do
    ~F"""
    <button
      :on-click={@click}
      type="button"
      class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
    >
      <span class="-ml-1 mr-2 h-5 w-5">
        <Component module={@icon} />
      </span>
      {@text}
    </button>
    """
  end
end
