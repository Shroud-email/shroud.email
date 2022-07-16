defmodule ShroudWeb.Components.LoggingWarning do
  use Surface.Component
  alias Shroud.Accounts.Logging

  prop current_user, :any, required: true

  def render(assigns) do
    ~F"""
    {#if Logging.any_logging_enabled?(@current_user)}
      <p class="alert alert-warning mb-6" role="alert">
        Logging is enabled on your account. Please <a href="mailto:hello@shroud.email" class="underline mx-1">contact support</a> if you did not expect this.
      </p>
    {/if}
    """
  end
end
