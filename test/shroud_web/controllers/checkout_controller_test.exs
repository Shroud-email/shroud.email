defmodule ShroudWeb.CheckoutControllerTest do
  use Shroud.DataCase, async: false

  import Shroud.AccountsFixtures

  alias Shroud.{Accounts, Repo}
  alias Shroud.Accounts.User

  describe "update_subscription_status (via webhook)" do
    test "sets user to :free when subscription is canceled" do
      user = user_fixture(%{status: :active})

      # Simulate what the webhook does: update stripe details with canceled status
      attrs = %{
        trial_expires_at: nil,
        plan_expires_at: nil,
        status: :free
      }

      Accounts.update_stripe_details!(user, attrs)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.status == :free
      assert is_nil(updated_user.plan_expires_at)
    end
  end
end
