defmodule Shroud.SentryReportingTest do
  use ExUnit.Case, async: true

  test "does not report rejected CSRF requests" do
    assert :excluded =
             Sentry.capture_exception(%Plug.CSRFProtection.InvalidCSRFTokenError{},
               event_source: :plug,
               before_send: Application.fetch_env!(:sentry, :before_send)
             )
  end

  test "still processes unexpected exceptions" do
    # Without a configured DSN, a non-filtered event is ignored only after the
    # before_send callback has allowed it through.
    assert :ignored =
             Sentry.capture_exception(%RuntimeError{message: "unexpected"},
               event_source: :plug,
               before_send: Application.fetch_env!(:sentry, :before_send)
             )
  end
end
