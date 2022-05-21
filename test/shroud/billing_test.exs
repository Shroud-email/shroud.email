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

    test "generates codes <120 characters long" do
      code = Billing.create_lifetime_code()
      assert String.length(code) < 120
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
  end
end
