defmodule Shroud.SentryReportingTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint ShroudWeb.Endpoint

  test "a tokenless login POST is rejected without creating a Sentry event" do
    Sentry.Test.setup_sentry()

    # ConnTest normally skips CSRF validation; remove that test-only bypass.
    conn = build_conn()
    conn = %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(conn, "/users/log_in", %{"0" => "unexpected payload"})
    end

    assert Sentry.Test.pop_sentry_reports() == []

    # The same endpoint request does reach Sentry when the filter is disabled.
    Sentry.Test.Config.put(before_send: fn event -> event end)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(conn, "/users/log_in", %{"0" => "unexpected payload"})
    end

    assert [%Sentry.Event{original_exception: %Plug.CSRFProtection.InvalidCSRFTokenError{}}] =
             Sentry.Test.pop_sentry_reports()
  end

  test "still processes unexpected exceptions" do
    Sentry.Test.setup_sentry()

    Sentry.capture_exception(%RuntimeError{message: "unexpected"}, event_source: :plug)

    assert [%Sentry.Event{original_exception: %RuntimeError{message: "unexpected"}}] =
             Sentry.Test.pop_sentry_reports()
  end
end
