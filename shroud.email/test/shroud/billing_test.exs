defmodule Shroud.Billing.BillingTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo

  alias Shroud.Accounts.LoopsJob
  alias Shroud.{Billing, Repo}
  import Shroud.AccountsFixtures
  import ExUnit.CaptureLog

  setup do
    user = user_fixture(%{status: :free})
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
      assert %DateTime{} = user.paid_converted_at

      assert_enqueued(
        worker: LoopsJob,
        args: %{action: "sync_loops", user_id: user.id}
      )
    end

    test "another code cannot repeat the conversion, even with a stale user struct", %{user: user} do
      assert :ok = Billing.redeem_lifetime_code(Billing.create_lifetime_code(), user)
      converted_at = Repo.reload!(user).paid_converted_at
      assert :ok = Billing.redeem_lifetime_code(Billing.create_lifetime_code(), user)
      assert Repo.reload!(user).paid_converted_at == converted_at
    end

    test "logs a successful redemption", %{user: user} do
      code = Billing.create_lifetime_code()

      assert capture_log(fn ->
               Billing.redeem_lifetime_code(code, user)
             end) =~ "#{user.email} redeemed a lifetime code!"
    end
  end
end
