defmodule ShroudWeb.Components.PopupAlert do
  use ShroudWeb, :live_component

  attr(:title, :string, required: true)
  attr(:text, :string, required: true)
  attr(:icon, :atom, required: true)

  slot(:inner_block, required: false, default: nil)
  slot(:buttons, required: false)

  def mount(socket) do
    {:ok, assign(socket, :show, false)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <div
        :if={@show}
        id={@id}
        phx-hook="Modal"
        x-data="{ open: false }"
        x-init="() => {
          setTimeout(() => open = true, 0)
          $watch('open', isOpen => {
            if (!isOpen) modalHook.modalClosing()
          })
        }"
        @keydown.escape.window="open = false"
        x-show="open"
        x-cloak
        class="relative z-10"
        aria-labelledby="modal-title"
        role="dialog"
        aria-modal="true"
      >
        <!--
          Background backdrop
        -->
        <div
          x-show="open"
          x-cloak
          x-transition:enter="ease-out duration-300"
          x-transition:enter-start="opacity-0"
          x-transition:enter-end="opacity-100"
          x-transition:leave="ease-in duration-200"
          x-transition:leave-start="opacity-100"
          x-transition:leave-end="opacity-0"
          class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
        />

        <div class="fixed z-10 inset-0 overflow-y-auto">
          <div class="flex items-end sm:items-center justify-center min-h-full p-4 text-center sm:p-0">
            <!--
              Modal panel
            -->
            <div
              x-on:click.away="open = false"
              x-show="open"
              x-cloak
              x-transition:enter="ease-out duration-300"
              x-transition:enter-start="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
              x-transition:enter-end="opacity-100 translate-y-0 sm:scale-100"
              x-transition:leave="ease-in duration-200"
              x-transition:leave-start="opacity-100 translate-y-0 sm:scale-100"
              x-transition:leave-end="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
              class="relative bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:max-w-lg sm:w-full"
            >
              <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <div class="sm:flex sm:items-start">
                  <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-gray-100 sm:mx-0 sm:h-10 sm:w-10">
                    <.icon name={@icon} class="h-6 w-6 text-gray-600" />
                  </div>
                  <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                    <h3 class="text-lg leading-6 font-medium text-gray-900" id="modal-title">
                      <%= @title %>
                    </h3>
                    <div class="mt-2">
                      <p class="text-sm text-gray-500"><%= @text %></p>
                    </div>
                    <%= render_slot(@inner_block) %>
                  </div>
                </div>
              </div>
              <div class="bg-gray-50 px-4 py-3 sm:px-6 flex flex-col sm:flex-row-reverse gap-1">
                <%= render_slot(@buttons) %>
                <.button alpine_click="open = false" text="Cancel" intent={:secondary} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Public API
  def show(dialog_id) do
    send_update(__MODULE__, id: dialog_id, show: true)
  end

  # Event handlers

  def handle_event("show", _, socket) do
    {:noreply, assign(socket, show: true)}
  end

  def handle_event("hide", _, socket) do
    {:noreply, assign(socket, show: false)}
  end
end
