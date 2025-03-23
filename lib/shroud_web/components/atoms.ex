defmodule ShroudWeb.Components.Atoms do
  alias Shroud.Accounts.Logging
  alias Phoenix.LiveView.JS

  use Phoenix.Component

  attr(:name, :atom, required: true)
  attr(:outline, :boolean, default: true)
  attr(:solid, :boolean, default: false)
  attr(:class, :string)

  def icon(assigns) do
    apply(Heroicons, assigns.name, [assigns])
  end

  attr(:text, :string, required: true)
  attr(:icon, :atom, required: false, default: nil)
  attr(:intent, :atom, default: :primary)
  attr(:type, :string, default: "button")
  attr(:disabled, :boolean, default: false)
  attr(:click, :string, required: false, default: nil)
  attr(:alpine_click, :string, required: false, default: nil)
  attr(:rest, :global)

  def button(assigns) do
    class =
      case assigns.intent do
        :primary -> "text-white bg-indigo-600 hover:bg-indigo-700"
        :secondary -> "text-indigo-700 bg-indigo-100 hover:bg-indigo-200"
        :danger -> "text-red-700 bg-red-100 hover:bg-red-200"
        :white -> "border-gray-300 text-gray-700 bg-white hover:bg-gray-50"
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <button
      @click={@alpine_click}
      phx-click={@click}
      type={@type}
      disabled={@disabled}
      class={@class <>
        " inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 justify-center disabled:opacity-80 disabled:cursor-wait"}
      {@rest}
    >
      <span :if={@icon} class="-ml-1 mr-2 h-5 w-5">
        <.icon name={@icon} />
      </span>
      <%= @text %>
    </button>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, required: false)
  attr(:icon, :atom, required: true)
  slot(:inner_block, required: false, default: nil)

  def empty_state(assigns) do
    ~H"""
    <div class="text-center">
      <.icon name={@icon} class="h-12 w-12 mx-auto text-gray-400" />
      <h3 class="mt-2 text-sm font-medium text-gray-900"><%= @title %></h3>
      <p :if={@description} class="mt-1 text-sm text-gray-500 max-w-lg mx-auto">
        <%= @description %>
      </p>
      <div class="mt-6">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr(:type, :string, default: "text")
  attr(:name, :string, required: true)
  attr(:placeholder, :string, required: false)

  def text_input(assigns) do
    ~H"""
    <div>
      <label for={@name} class="sr-only">{@name}</label>
      <div class="mt-1">
        <input
          type={@type}
          name={@name}
          id={@name}
          placeholder={@placeholder}
          class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
        />
      </div>
    </div>
    """
  end

  attr(:on, :boolean, required: true)
  attr(:click, :string, required: true)

  def toggle(assigns) do
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

    assigns = assign(assigns, :button_class, button_class)
    assigns = assign(assigns, :toggle_class, toggle_class)
    assigns = assign(assigns, :sr_text, sr_text)

    ~H"""
    <button type="button" class={@button_class} role="switch" aria-checked={@on} phx-click={@click}>
      <span class="sr-only">
        <%= @sr_text %>
      </span>
      <span aria-hidden="true" class={@toggle_class} />
    </button>
    """
  end

  attr(:icon, :atom, required: false)
  attr(:type, :atom, required: true)
  attr(:title, :string, required: true)
  slot(:inner_block, required: true)

  def alert(assigns) do
    [icon_class, alert_class] =
      case assigns.type do
        :info ->
          ["text-blue-400", "bg-blue-50 text-blue-700 border-blue-100"]

        :warning ->
          ["text-yellow-400", "bg-yellow-50 text-yellow-700 border-yellow-100"]

        :error ->
          ["text-red-400", "bg-red-50 text-red-700 border-red-100"]
      end

    assigns = assign(assigns, :icon_class, icon_class)
    assigns = assign(assigns, :alert_class, alert_class)

    ~H"""
    <div class={"rounded-md p-4 flex text-sm border mb-6 " <> @alert_class}>
      <div class="flex-shrink-0">
        <.icon name={@icon} solid class={"text-base h-5 w-5 " <> @icon_class} />
      </div>
      <div class="ml-3">
        <h3 class="font-medium text-yellow-800">
          <%= @title %>
        </h3>
        <div class="mt-2 text-sm">
          <p>
            <%= render_slot(@inner_block) %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr(:current_user, :any, required: true)

  def logging_warning(assigns) do
    ~H"""
    <p :if={Logging.any_logging_enabled?(@current_user)} class="alert alert-warning mb-6" role="alert">
      Logging is enabled on your account. Please
      <a href="mailto:hello@shroud.email" class="underline mx-1">contact support</a>
      if you did not expect this.
    </p>
    """
  end

  attr(:flash, :any, required: true)
  attr(:kind, :atom, required: true)

  def notification(assigns) do
    [icon, icon_class] =
      case assigns.kind do
        :success -> [:check_circle, "text-green-400"]
        :info -> [:information_circle, "text-gray-400"]
        :error -> [:exclamation_circle, "text-red-400"]
      end

    assigns = assign(assigns, :icon, icon)
    assigns = assign(assigns, :icon_class, icon_class)

    ~H"""
    <button
      :if={Phoenix.Flash.get(@flash, @kind)}
      phx-hook="Notification"
      id={"flash-#{@kind}"}
      class="fade-in-translate max-w-sm w-full bg-white shadow-lg rounded-lg pointer-events-auto ring-1 ring-black ring-opacity-5 overflow-hidden hover:shadow-xl transition-all duration-100"
      phx-click={close("#flash", @kind)}
    >
      <div class="p-4">
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <.icon name={@icon} class={"h-6 w-6 " <> @icon_class} />
          </div>
          <div class="ml-3 w-0 flex-1 pt-0.5">
            <p class="text-left text-sm font-medium text-gray-900">
              <%= Phoenix.Flash.get(@flash, @kind) %>
            </p>
          </div>
        </div>
      </div>
    </button>
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
