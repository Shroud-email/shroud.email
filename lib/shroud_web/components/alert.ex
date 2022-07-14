defmodule ShroudWeb.Components.Alert do
  use Surface.Component

  prop icon, :module, required: false
  prop type, :atom, required: true
  prop title, :string, required: true
  slot default, required: true

  def render(assigns) do
    [icon_class, alert_class] =
      case assigns.type do
        :info ->
          ["text-blue-400", "bg-blue-50 text-blue-700 border-blue-100"]

        :warning ->
          ["text-yellow-400", "bg-yellow-50 text-yellow-700 border-yellow-100"]

        :error ->
          ["text-red-400", "bg-red-50 text-red-700 border-red-100"]
      end

    ~F"""
    <div class={"rounded-md p-4 flex text-sm border mb-6 " <> alert_class}>
      <div class="flex-shrink-0">
        <Component module={@icon} class={"text-base h-5 w-5 " <> icon_class} />
      </div>
      <div class="ml-3">
        <h3 class="font-medium text-yellow-800">
          {@title}
        </h3>
        <div class="mt-2 text-sm">
          <p>
            <#slot />
          </p>
        </div>
      </div>
    </div>
    """
  end
end
