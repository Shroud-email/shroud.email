defmodule ShroudWeb.Components.Button do
  use Surface.Component

  prop text, :string, required: true
  prop icon, :module, required: false
  prop intent, :atom, default: :primary
  prop type, :string, default: "button"
  prop disabled, :boolean, default: false
  prop click, :event, required: false
  prop alpine_click, :string, required: false

  def render(assigns) do
    class =
      case assigns.intent do
        :primary -> "text-white bg-indigo-600 hover:bg-indigo-700"
        :secondary -> "text-indigo-700 bg-indigo-100 hover:bg-indigo-200"
        :danger -> "text-red-700 bg-red-100 hover:bg-red-200"
        :white -> "border-gray-300 text-gray-700 bg-white hover:bg-gray-50"
      end

    ~F"""
    <button
      @click={@alpine_click}
      :on-click={@click}
      {=@type}
      {=@disabled}
      class={class <>
        " inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 justify-center disabled:opacity-80 disabled:cursor-wait"}
    >
      <span :if={@icon} class="-ml-1 mr-2 h-5 w-5">
        <Component module={@icon} />
      </span>
      {@text}
    </button>
    """
  end
end
