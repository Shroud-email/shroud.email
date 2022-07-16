defmodule ShroudWeb.Components.TextInput do
  use Surface.Component

  prop type, :string, default: "text"
  prop name, :string, required: true
  prop placeholder, :string, required: false

  def render(assigns) do
    ~F"""
    <div>
      <label for={@name} class="sr-only">{@name}</label>
      <div class="mt-1">
        <input
          {=@type}
          {=@name}
          id={@name}
          {=@placeholder}
          class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
        />
      </div>
    </div>
    """
  end
end
