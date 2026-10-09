defmodule Shroud.ErrorReporter do
  def before_send(%Sentry.Event{
        original_exception: %Plug.CSRFProtection.InvalidCSRFTokenError{}
      }),
      do: nil

  def before_send(event), do: event
end
