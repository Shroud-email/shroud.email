defmodule ShroudWeb.Components.EmptyState do
  use Surface.Component

  prop title, :string, required: true
  prop description, :string, required: false
  @doc "The HeroIcons component to use"
  prop icon, :module, required: true
  slot default, required: false

  @spec render(map) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~F"""
    <div class="text-center">
      <Component module={@icon} class="h-12 w-12 mx-auto text-gray-400" />
      <h3 class="mt-2 text-sm font-medium text-gray-900">{@title}</h3>
      <p :if={@description} class="mt-1 text-sm text-gray-500 max-w-lg mx-auto">
        {@description}
      </p>
      <div class="mt-6">
        <#slot />
      </div>
    </div>
    """
  end
end
