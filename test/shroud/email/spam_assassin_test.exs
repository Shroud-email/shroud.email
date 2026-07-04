defmodule Shroud.Email.SpamAssassinTest do
  use ExUnit.Case, async: true
  import Mox

  alias Shroud.Email.SpamAssassin

  # The mock is registered in test_helper.exs as Shroud.MockSpamAssassin
  # and bound to the app env :spamassassin_module.

  setup do
    # Always verify expectations and stub the module by default so tests
    # that don't care about scanning don't have to set it up.
    stub_with(Shroud.MockSpamAssassin, Shroud.Email.SpamAssassin.Stub)
    :ok
  end

  describe "scan/1" do
    test "returns :disabled when SpamAssassin is not enabled" do
      # Disable via app env for this test
      original = Application.get_env(:shroud, :spamassassin, [])
      Application.put_env(:shroud, :spamassassin, Keyword.put(original, :enabled, false))

      try do
        assert SpamAssassin.scan("Subject: hi\r\n\r\nbody") == :disabled
      after
        Application.put_env(:shroud, :spamassassin, original)
      end
    end

    test "returns the X-Spam-Status value via the configured module" do
      # Use a stub implementation that returns a canned value
      Shroud.MockSpamAssassin
      |> expect(:scan, fn _raw ->
        {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"}
      end)

      Application.put_env(:shroud, :spamassassin, enabled: true, module: Shroud.MockSpamAssassin)

      assert SpamAssassin.scan("Subject: hi\r\n\r\nbody") ==
               {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"}
    after
      Application.put_env(:shroud, :spamassassin, Application.get_env(:shroud, :spamassassin, []))
    end
  end
end
