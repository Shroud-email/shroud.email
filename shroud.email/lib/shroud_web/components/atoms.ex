defmodule ShroudWeb.Components.Atoms do
  alias Shroud.Accounts.Logging

  use Phoenix.Component, global_prefixes: ~w(x-)

  attr(:name, :atom, required: true)
  attr(:outline, :boolean, default: true)
  attr(:solid, :boolean, default: false)
  attr(:class, :string)

  def icon(assigns) do
    apply(Heroicons, assigns.name, [assigns])
  end

  attr(:text, :string, default: nil)
  attr(:icon, :atom, required: false, default: nil)
  attr(:intent, :atom, default: :primary)
  attr(:type, :string, default: "button")
  attr(:disabled, :boolean, default: false)
  attr(:click, :any, required: false, default: nil)
  attr(:alpine_click, :string, required: false, default: nil)
  attr(:class, :any, default: nil)
  attr(:href, :any, default: nil)
  attr(:navigate, :string, default: nil)
  attr(:patch, :string, default: nil)
  attr(:size, :atom, default: :normal, values: [:normal, :icon, :compact])
  attr(:shape, :atom, default: :default, values: [:default, :left, :right, :top_right])
  attr(:rest, :global, include: ~w(name value form target download rel))
  slot(:inner_block)

  def button(assigns) do
    radius =
      case assigns.shape do
        :default -> if assigns.intent != :unstyled, do: "rounded-button"
        :left -> "rounded-l-button"
        :right -> "rounded-r-button"
        :top_right -> "rounded-tr-button"
      end

    assigns = assign(assigns, :button_class, button_colors(assigns.intent))
    assigns = assign(assigns, :padding, button_padding(assigns.size, assigns.intent))
    assigns = assign(assigns, :radius, radius)

    assigns =
      assign(
        assigns,
        :base_class,
        if(assigns.intent != :unstyled,
          do:
            "button-feedback inline-flex items-center justify-center border text-sm font-medium focus:outline-hidden focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-indigo-500 dark:focus-visible:ring-offset-gray-900"
        )
      )

    ~H"""
    <.link
      :if={!@disabled && (@href || @navigate || @patch)}
      href={@href}
      navigate={@navigate}
      patch={@patch}
      class={[
        @base_class,
        @intent != :unstyled && "button-feedback-press",
        @intent not in [:text, :danger_text, :unstyled] && "shadow-xs",
        @button_class,
        @padding,
        @radius,
        @class
      ]}
      {@rest}
    >
      <span :if={@icon} class="-ml-1 mr-2 h-5 w-5">
        <.icon name={@icon} />
      </span>
      {@text}
      {render_slot(@inner_block)}
    </.link>
    <button
      :if={@disabled || !(@href || @navigate || @patch)}
      @click={@alpine_click}
      phx-click={@click}
      type={@type}
      disabled={@disabled}
      class={[
        @base_class,
        @intent != :unstyled && "button-feedback-press",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        @intent not in [:text, :danger_text, :unstyled] && "shadow-xs",
        @button_class,
        @padding,
        @radius,
        @class
      ]}
      {@rest}
    >
      <span :if={@icon} class="-ml-1 mr-2 h-5 w-5">
        <.icon name={@icon} />
      </span>
      {@text}
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_colors(intent) do
    case intent do
      :primary ->
        "border-transparent text-white bg-indigo-600 not-disabled:hover:bg-indigo-700 dark:bg-indigo-500 dark:not-disabled:hover:bg-indigo-400"

      :secondary ->
        "border-transparent text-indigo-700 bg-indigo-100 not-disabled:hover:bg-indigo-200 dark:text-indigo-300 dark:bg-indigo-900/50 dark:not-disabled:hover:bg-indigo-900/70"

      :danger ->
        "border-transparent text-red-700 bg-red-100 not-disabled:hover:bg-red-200 dark:text-red-300 dark:bg-red-900/50 dark:not-disabled:hover:bg-red-900/70"

      :white ->
        "border-gray-300 text-gray-700 bg-white not-disabled:hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:bg-gray-700 dark:not-disabled:hover:bg-gray-600"

      :text ->
        "border-0 shadow-none bg-transparent text-indigo-600 not-disabled:hover:text-indigo-500 dark:text-indigo-400 dark:not-disabled:hover:text-indigo-400"

      :danger_text ->
        "border-0 shadow-none bg-transparent text-red-700 not-disabled:hover:text-red-500 dark:text-red-400 dark:not-disabled:hover:text-red-500"

      :unstyled ->
        nil
    end
  end

  defp button_padding(:icon, _intent), do: "p-2"
  defp button_padding(:compact, _intent), do: "p-1"
  defp button_padding(:normal, :unstyled), do: nil
  defp button_padding(:normal, intent) when intent in [:text, :danger_text], do: "p-0"
  defp button_padding(:normal, _intent), do: "px-4 py-2"

  attr(:title, :string, required: true)
  attr(:description, :string, required: false)
  attr(:icon, :atom, required: true)
  slot(:inner_block, required: false)

  def empty_state(assigns) do
    ~H"""
    <div class="text-center">
      <.icon name={@icon} class="h-12 w-12 mx-auto text-gray-400" />
      <h3 class="mt-2 text-sm font-medium text-gray-900 dark:text-gray-100">{@title}</h3>
      <p :if={@description} class="mt-1 text-sm text-gray-500 dark:text-gray-400 max-w-lg mx-auto">
        {@description}
      </p>
      <div class="mt-6">
        {render_slot(@inner_block)}
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
          class="shadow-xs focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400"
        />
      </div>
    </div>
    """
  end

  attr(:on, :boolean, required: true)
  attr(:click, :string, required: true)

  def toggle(assigns) do
    button_class =
      "relative inline-flex shrink-0 h-6 w-11 border-2 border-transparent rounded-full cursor-pointer transition-colors ease-in-out duration-200 focus:outline-hidden focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 dark:focus:ring-offset-gray-900"

    toggle_class =
      "pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow-sm transform ring-0 transition ease-in-out duration-200"

    [button_class, toggle_class] =
      if assigns.on do
        [button_class <> " bg-indigo-600 dark:bg-indigo-500", toggle_class <> " translate-x-5"]
      else
        [button_class <> " bg-gray-200 dark:bg-gray-600", toggle_class <> " translate-x-0"]
      end

    sr_text = if assigns.on, do: "Disable", else: "Enable"

    assigns = assign(assigns, :button_class, button_class)
    assigns = assign(assigns, :toggle_class, toggle_class)
    assigns = assign(assigns, :sr_text, sr_text)

    ~H"""
    <.button intent={:unstyled} class={@button_class} role="switch" aria-checked={@on} click={@click}>
      <span class="sr-only">
        {@sr_text}
      </span>
      <span aria-hidden="true" class={@toggle_class} />
    </.button>
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
          [
            "text-blue-400",
            "bg-blue-50 text-blue-700 border-blue-100 dark:bg-blue-900/30 dark:text-blue-300 dark:border-blue-800"
          ]

        :warning ->
          [
            "text-yellow-400",
            "bg-yellow-50 text-yellow-700 border-yellow-100 dark:bg-yellow-900/30 dark:text-yellow-300 dark:border-yellow-800"
          ]

        :error ->
          [
            "text-red-400",
            "bg-red-50 text-red-700 border-red-100 dark:bg-red-900/30 dark:text-red-300 dark:border-red-800"
          ]
      end

    assigns = assign(assigns, :icon_class, icon_class)
    assigns = assign(assigns, :alert_class, alert_class)

    ~H"""
    <div class={"rounded-md p-4 flex text-sm border mb-6 " <> @alert_class}>
      <div class="shrink-0">
        <.icon name={@icon} solid class={"text-base h-5 w-5 " <> @icon_class} />
      </div>
      <div class="ml-3">
        <h3 class="font-medium text-yellow-800 dark:text-yellow-200">
          {@title}
        </h3>
        <div class="mt-2 text-sm">
          <p>
            {render_slot(@inner_block)}
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
end
