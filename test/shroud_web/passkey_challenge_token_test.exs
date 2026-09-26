defmodule ShroudWeb.PasskeyChallengeTokenTest do
  use ShroudWeb.ConnCase

  alias ShroudWeb.PasskeyChallengeToken

  test "a signed challenge is bound to the session CSRF secret" do
    first = build_conn() |> init_test_session(%{_csrf_token: "first-secret"})
    second = build_conn() |> init_test_session(%{_csrf_token: "other-secret"})
    signed = PasskeyChallengeToken.sign(first, "challenge")

    assert PasskeyChallengeToken.verify(first, signed) == {:ok, "challenge"}
    assert PasskeyChallengeToken.verify(second, signed) == :error
  end

  test "a challenge signed without a CSRF session cannot be used by another empty session" do
    first = build_conn() |> init_test_session(%{})
    second = build_conn() |> init_test_session(%{})
    signed = PasskeyChallengeToken.sign(first, "challenge")

    assert PasskeyChallengeToken.verify(second, signed) == :error
  end
end
