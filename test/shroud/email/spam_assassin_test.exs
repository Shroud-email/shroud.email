defmodule Shroud.Email.SpamAssassinTest do
  use ExUnit.Case, async: true
  import Mox

  alias Shroud.Email.SpamAssassin

  # The mock is registered in test_helper.exs as Shroud.MockSpamAssassin
  # and bound to the app env :spamassassin.

  setup do
    # Always verify expectations and stub the module by default so tests
    # that don't care about scanning don't have to set it up.
    stub_with(Shroud.MockSpamAssassin, Shroud.Email.SpamAssassin.Stub)
    verify_on_exit!()
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
      original = Application.get_env(:shroud, :spamassassin, [])

      # Use a stub implementation that returns a canned value
      Shroud.MockSpamAssassin
      |> expect(:scan, fn _raw ->
        {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"}
      end)

      Application.put_env(:shroud, :spamassassin, enabled: true, module: Shroud.MockSpamAssassin)

      try do
        assert SpamAssassin.scan("Subject: hi\r\n\r\nbody") ==
                 {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"}
      after
        Application.put_env(:shroud, :spamassassin, original)
      end
    end
  end

  describe "Client.parse_x_spam_status/1" do
    alias Shroud.Email.SpamAssassin.Client

    test "extracts the X-Spam-Status header value (case-insensitive)" do
      output =
        "Subject: hi\r\nX-Spam-Status: No, score=-1.0 required=5.0 tests=NONE version=3.4.1\r\n\r\nbody"

      assert Client.parse_x_spam_status(output) ==
               {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"}
    end

    test "extracts the header when spam is detected" do
      output =
        "X-Spam-Status: Yes, score=8.2 required=5.0 tests=FOO,BAR version=3.4.1\r\nSubject: hi\r\n\r\nbody"

      assert Client.parse_x_spam_status(output) ==
               {:ok, "Yes, score=8.2 required=5.0 tests=FOO,BAR version=3.4.1"}
    end

    test "handles lowercase header name" do
      output = "x-spam-status: No, score=0.0 required=5.0\r\n\r\nbody"
      assert Client.parse_x_spam_status(output) == {:ok, "No, score=0.0 required=5.0"}
    end

    test "returns :error when the header is absent" do
      assert Client.parse_x_spam_status("Subject: hi\r\n\r\nbody") == :error
    end

    test "returns :error on empty input" do
      assert Client.parse_x_spam_status("") == :error
    end
  end

  describe "Client.scan/1 shell-out" do
    alias Shroud.Email.SpamAssassin.Client

    test "returns {:error, _} when spamc binary is missing" do
      original = Application.get_env(:shroud, :spamassassin, [])

      # Point at a path that does not exist on the test machine.
      Application.put_env(:shroud, :spamassassin,
        enabled: true,
        module: Client,
        spamc_path: "/nonexistent/spamc-#{System.unique_integer([:positive])}"
      )

      try do
        assert {:error, _} = Client.scan("Subject: hi\r\n\r\nbody")
      after
        Application.put_env(:shroud, :spamassassin, original)
      end
    end
  end
end
