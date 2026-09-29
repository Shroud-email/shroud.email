defmodule ShroudWeb.LayoutsTest do
  use ExUnit.Case, async: true

  alias Shroud.Accounts.User
  alias ShroudWeb.Layouts

  # Compute the expected HMAC outside of Application config so the test
  # is deterministic and independent of the configured token.
  @token "test-secret"
  @email "user@example.com"
  @expected_hash :crypto.mac(:hmac, :sha256, @token, @email) |> Base.encode16(case: :lower)

  describe "chatwoot_base_url/0" do
    test "returns the configured CHATWOOT_BASE_URL" do
      previous = Application.get_env(:shroud, :chatwoot_base_url)
      Application.put_env(:shroud, :chatwoot_base_url, "https://support.example.com")

      try do
        assert Layouts.chatwoot_base_url() == "https://support.example.com"
      after
        Application.put_env(:shroud, :chatwoot_base_url, previous)
      end
    end

    test "returns nil when not configured" do
      previous = Application.get_env(:shroud, :chatwoot_base_url)
      Application.delete_env(:shroud, :chatwoot_base_url)

      try do
        assert is_nil(Layouts.chatwoot_base_url())
      after
        Application.put_env(:shroud, :chatwoot_base_url, previous)
      end
    end
  end

  describe "chatwoot_identifier_hash/1" do
    test "returns an HMAC-SHA256 hex digest for a user" do
      previous = Application.get_env(:shroud, :chatwoot_hmac_token)
      Application.put_env(:shroud, :chatwoot_hmac_token, @token)

      user = %User{email: @email}

      try do
        assert Layouts.chatwoot_identifier_hash(user) == @expected_hash
        # SHA-256 hex digests are 64 chars
        assert byte_size(Layouts.chatwoot_identifier_hash(user)) == 64
      after
        Application.put_env(:shroud, :chatwoot_hmac_token, previous)
      end
    end

    test "returns nil when no user is signed in" do
      assert is_nil(Layouts.chatwoot_identifier_hash(nil))
    end

    test "returns nil when no HMAC token is configured" do
      previous = Application.get_env(:shroud, :chatwoot_hmac_token)
      Application.delete_env(:shroud, :chatwoot_hmac_token)

      user = %User{email: @email}

      try do
        assert is_nil(Layouts.chatwoot_identifier_hash(user))
      after
        Application.put_env(:shroud, :chatwoot_hmac_token, previous)
      end
    end

    test "returns nil when the HMAC token is an empty string" do
      previous = Application.get_env(:shroud, :chatwoot_hmac_token)
      Application.put_env(:shroud, :chatwoot_hmac_token, "")

      user = %User{email: @email}

      try do
        assert is_nil(Layouts.chatwoot_identifier_hash(user))
      after
        Application.put_env(:shroud, :chatwoot_hmac_token, previous)
      end
    end

    test "produces different hashes for different emails" do
      previous = Application.get_env(:shroud, :chatwoot_hmac_token)
      Application.put_env(:shroud, :chatwoot_hmac_token, @token)

      try do
        a = Layouts.chatwoot_identifier_hash(%User{email: "a@example.com"})
        b = Layouts.chatwoot_identifier_hash(%User{email: "b@example.com"})
        assert a != b
      after
        Application.put_env(:shroud, :chatwoot_hmac_token, previous)
      end
    end
  end
end
