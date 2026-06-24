defmodule Shroud.Billing.BillingTest do
  use Shroud.DataCase, async: true
  alias Shroud.{Billing, Repo}
  import Shroud.AccountsFixtures
  import ExUnit.CaptureLog

  setup do
    user = user_fixture(%{status: :trial})
    %{user: user}
  end

  describe "create_lifetime_code/0" do
    test "creates and redeems a code", %{user: user} do
      code = Billing.create_lifetime_code()
      assert :ok == Billing.redeem_lifetime_code(code, user)
    end

    test "generates codes <150 characters long" do
      code = Billing.create_lifetime_code()
      assert String.length(code) < 150
    end
  end

  describe "redeem_lifetime_code/2" do
    test "rejects invalid codes", %{user: user} do
      code = Billing.create_lifetime_code()
      assert {:error, :invalid_code} == Billing.redeem_lifetime_code(code <> "x", user)
    end

    test "rejects empty codes", %{user: user} do
      assert {:error, :invalid_code} == Billing.redeem_lifetime_code("", user)
    end

    test "rejects already-used codes", %{user: user} do
      code = Billing.create_lifetime_code()
      Billing.redeem_lifetime_code(code, user)

      assert {:error, :already_redeemed} == Billing.redeem_lifetime_code(code, user)
    end

    test "sets the user's status to lifetime", %{user: user} do
      code = Billing.create_lifetime_code()

      assert :ok == Billing.redeem_lifetime_code(code, user)
      user = Repo.reload!(user)
      assert user.status == :lifetime
      assert is_nil(user.trial_expires_at)
    end

    test "logs a successful redemption", %{user: user} do
      code = Billing.create_lifetime_code()

      assert capture_log(fn ->
               Billing.redeem_lifetime_code(code, user)
             end) =~ "#{user.email} redeemed a lifetime code!"
    end

    test "returns an error (not :ok) when the transaction fails" do
      code = Billing.create_lifetime_code()

      # An unpersisted user has a nil id, so the lifetime_code changeset
      # (redeemed_by_id is required) fails inside the transaction.
      unsaved_user = %Shroud.Accounts.User{email: "ghost@example.com"}

      log =
        capture_log(fn ->
          assert {:error, :redemption_failed} =
                   Billing.redeem_lifetime_code(code, unsaved_user)
        end)

      # The success message must not be logged when redemption failed.
      refute log =~ "redeemed a lifetime code!"
      # And the code must not have been consumed.
      assert is_nil(Repo.get_by(Billing.LifetimeCode, code: code))
    end
  end
end
