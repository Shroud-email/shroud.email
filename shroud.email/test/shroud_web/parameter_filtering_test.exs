defmodule ShroudWeb.ParameterFilteringTest do
  use ExUnit.Case, async: true

  test "OAuth, MCP and passkey parameters are redacted without hiding ordinary parameters" do
    params = %{
      "password" => "private-password",
      "secret" => "private-secret",
      "access_token" => "private-token",
      "code" => "private-code",
      "code_verifier" => "private-verifier",
      "approval" => "private-approval",
      "arguments" => %{"notes" => "private-notes"},
      "rawId" => "private-id",
      "userHandle" => "private-handle",
      "authenticatorData" => "private-authenticator",
      "clientDataJSON" => "private-client-data",
      "attestationObject" => "private-attestation",
      "signature" => "private-signature",
      "client_id" => "public-client",
      "grant_type" => "authorization_code"
    }

    filtered = Phoenix.Logger.filter_values(params)

    for key <- Map.keys(params) -- ["client_id", "grant_type"] do
      assert filtered[key] == "[FILTERED]"
    end

    assert filtered["client_id"] == "public-client"
    assert filtered["grant_type"] == "authorization_code"
  end
end
