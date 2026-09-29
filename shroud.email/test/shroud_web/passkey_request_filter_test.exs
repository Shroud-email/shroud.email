defmodule ShroudWeb.PasskeyRequestFilterTest do
  use ExUnit.Case, async: true

  test "Phoenix logs do not include passkey request material" do
    params = %{
      "current_password" => "password-value",
      "token" => "signed-token",
      "rawId" => "credential-id",
      "userHandle" => "user-handle",
      "authenticatorData" => "auth-data",
      "clientDataJSON" => "client-data",
      "attestationObject" => "attestation",
      "signature" => "signature-value"
    }

    filtered = Phoenix.Logger.filter_values(params)
    assert Map.keys(filtered) == Map.keys(params)
    assert Enum.all?(Map.values(filtered), &(&1 == "[FILTERED]"))
  end

  test "Sentry request context omits passkey bodies, including the enrollment password" do
    for path <- ["/settings/passkeys/options", "/settings/passkeys", "/users/passkeys"] do
      conn =
        Plug.Test.conn(:post, path)
        |> Map.put(:params, %{"current_password" => "private", "clientDataJSON" => "assertion"})

      Sentry.PlugContext.call(conn, body_scrubber: {ShroudWeb.Endpoint, :sentry_body})

      assert Sentry.Context.get_all().request.data == %{}
    end
  end
end
