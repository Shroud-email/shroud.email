defmodule ShroudWeb.PaddleCheckoutIdentityTest do
  use ExUnit.Case, async: true

  alias ShroudWeb.PaddleCheckoutIdentity

  test "round-trips the authenticated user and configured price" do
    token = PaddleCheckoutIdentity.sign(123)

    assert {:ok, %{user_id: 123, price_id: "pri_test_yearly"}} =
             PaddleCheckoutIdentity.verify(token)
  end

  test "rejects a modified identity" do
    token = PaddleCheckoutIdentity.sign(123)

    assert {:error, :invalid} = PaddleCheckoutIdentity.verify("x" <> token)
  end
end
