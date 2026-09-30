defmodule Shroud.Accounts.TOTPTest do
  use Shroud.DataCase

  alias Shroud.Accounts.TOTP
  alias Shroud.Repo

  import Shroud.AccountsFixtures

  setup do
    user = user_fixture()

    %{user: user}
  end

  describe "create_secret/0" do
    test "creates a secret" do
      secret = TOTP.create_secret()

      refute is_nil(secret)
    end
  end

  describe "otp_uri/2" do
    test "creates a valid OTP URI", %{user: user} do
      uri = TOTP.otp_uri(user, "deadbeef")

      regex = ~r/otpauth:\/\/totp\/Shroud.email:user-\d+@example.com\?secret=MRSWCZDCMVSWM/
      assert Regex.match?(regex, uri)
    end
  end

  describe "enable_totp!/2" do
    test "enables TOTP", %{user: user} do
      secret = TOTP.create_secret()
      TOTP.enable_totp!(user, secret)
      user = Repo.reload!(user)

      assert user.totp_secret == secret
      assert user.totp_enabled
    end

    test "creates backup codes", %{user: user} do
      secret = TOTP.create_secret()
      TOTP.enable_totp!(user, secret)
      user = Repo.reload!(user)

      assert Enum.all?(user.totp_backup_codes, &Regex.match?(~r/\d{8}/, &1))
      assert length(user.totp_backup_codes) == 8
    end
  end

  describe "disable_totp!/2" do
    test "disables TOTP", %{user: user} do
      TOTP.enable_totp!(user, TOTP.create_secret())
      user = TOTP.disable_totp!(user)

      refute user.totp_enabled
    end
  end

  describe "valid_code?/2" do
    test "falls back to consuming backup code", %{user: user} do
      TOTP.enable_totp!(user, TOTP.create_secret())
      user = Repo.reload!(user)

      assert TOTP.valid_code?(user, user.totp_secret, hd(user.totp_backup_codes))
      user = Repo.reload!(user)
      assert length(user.totp_backup_codes) == 7
    end
  end
end
