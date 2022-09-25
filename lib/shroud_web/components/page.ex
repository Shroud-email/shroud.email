defmodule ShroudWeb.Components.Page do
  use Surface.Component
  alias Surface.Components.LiveRedirect
  alias ShroudWeb.Components.{Notification, LoggingWarning}

  prop page_title_url, :string, default: nil
  prop page_title, :string, required: true
  prop subpage_title, :string, default: nil
  prop flash, :any, required: true
  prop current_user, :any, required: true

  slot default, required: true

  def render(assigns) do
    ~F"""
    <header class="bg-white shadow-sm">
      <div class="max-w-7xl mx-auto py-4 px-4 sm:px-6 lg:px-8 flex items-center">
        {#if @page_title_url}
          <LiveRedirect to={@page_title_url} class="text-gray-900 hover:text-indigo-600 transition-colors">
            <h1 class="text-lg leading-6 font-semibold">
              {@page_title}
            </h1>
          </LiveRedirect>
        {#else}
          <h1 class="text-lg leading-6 font-semibold text-gray-900">
            {@page_title}
          </h1>
        {/if}
        {#if @subpage_title}
          <Heroicons.Solid.ChevronRightIcon class="flex-shrink-0 h-5 w-5 text-gray-500 ml-1" />
          <h2 class="text-sm text-gray-700 ml-1">{@subpage_title}</h2>
        {/if}
      </div>
    </header>

    <main>
      <div class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <div class="px-4 py-4 sm:px-0">
          <LoggingWarning {=@current_user} />
          <#slot />
        </div>
      </div>
    </main>

    {!-- Notification container --}
    <div
      aria-live="assertive"
      class="fixed inset-0 flex items-end px-4 py-6 pointer-events-none sm:p-6 sm:items-start"
    >
      <div class="w-full flex flex-col items-center space-y-4 sm:items-end">
        <Notification flash={@flash} kind={:success} />
        <Notification flash={@flash} kind={:info} />
        <Notification flash={@flash} kind={:error} />
      </div>
    </div>
    """
  end
end
