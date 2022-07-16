defmodule ShroudWeb.Components.Notification do
  use Surface.Component
  alias Phoenix.LiveView.JS

  prop flash, :any, required: true
  prop kind, :atom, required: true

  def render(assigns) do
    [icon, icon_class] =
      case assigns.kind do
        :success -> [Heroicons.Outline.CheckCircleIcon, "text-green-400"]
        :info -> [Heroicons.Outline.InformationCircleIcon, "text-gray-400"]
        :error -> [Heroicons.Outline.ExclamationCircleIcon, "text-red-400"]
      end

    ~F"""
    {#if live_flash(@flash, @kind)}
      <button
        :hook="Hook"
        id="flash"
        class="fade-in-translate max-w-sm w-full bg-white shadow-lg rounded-lg pointer-events-auto ring-1 ring-black ring-opacity-5 overflow-hidden hover:shadow-xl transition-all duration-100"
        phx-click={close("#flash", @kind)}
      >
        <div class="p-4">
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <Component module={icon} class={"h-6 w-6 " <> icon_class} />
            </div>
            <div class="ml-3 w-0 flex-1 pt-0.5">
              <p class="text-left text-sm font-medium text-gray-900">{live_flash(@flash, @kind)}</p>
            </div>
          </div>
        </div>
      </button>
    {/if}
    """
  end

  defp close(selector, kind) do
    JS.push("lv:clear-flash", value: %{key: kind})
    |> JS.remove_class("fade-in-translate")
    |> JS.hide(
      to: selector,
      time: 100,
      transition: {
        "transition ease-in duration-100",
        "opacity-100",
        "opacity-0"
      }
    )
  end
end
