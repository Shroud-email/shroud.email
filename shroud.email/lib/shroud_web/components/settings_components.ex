defmodule ShroudWeb.SettingsComponents do
  use ShroudWeb, :component

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :rest, :global, include: ~w(required minlength maxlength inputmode autocomplete pattern)

  def input(assigns) do
    ~H"""
    <label for={@id || @field.id} class="block text-sm font-medium text-gray-700 dark:text-gray-300">
      {@label}
    </label>
    <input
      type={@type}
      id={@id || @field.id}
      name={@name || @field.name}
      value={if @type != "password", do: @field.value}
      class="mt-1 block w-full border border-gray-300 rounded-md shadow-xs py-2 px-3 focus:outline-hidden focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400"
      {@rest}
    />
    <span :for={error <- @field.errors} class="invalid-feedback">{translate_error(error)}</span>
    """
  end
end
