defmodule ShroudWeb.PendingTOTPTest do
  use ExUnit.Case, async: true

  alias ShroudWeb.PendingTOTP

  setup do
    server = start_supervised!({PendingTOTP, name: __MODULE__})
    %{server: server}
  end

  test "pending state is session-scoped and can be cleared", %{server: server} do
    secret = Shroud.Accounts.TOTP.create_secret()
    assert PendingTOTP.get(:first, server) == nil
    :ok = PendingTOTP.put(:first, {:enable, secret}, server)
    :ok = PendingTOTP.put(:second, :disable, server)
    assert PendingTOTP.get(:first, server) == {:enable, secret}
    assert PendingTOTP.get(:second, server) == :disable
    :ok = PendingTOTP.delete(:first, server)
    assert PendingTOTP.get(:first, server) == nil
    assert PendingTOTP.get(:second, server) == :disable
  end

  test "expired entries are rejected on read and removed by cleanup", %{server: server} do
    now = System.monotonic_time(:millisecond)

    :sys.replace_state(server, fn _ ->
      %{
        expired: {now - 1, :disable},
        abandoned: {now - 1, :disable},
        active: {now + :timer.minutes(30), :disable}
      }
    end)

    assert PendingTOTP.get(:expired, server) == nil
    refute Map.has_key?(:sys.get_state(server), :expired)
    send(server, :expire)
    assert Map.keys(:sys.get_state(server)) == [:active]
    assert PendingTOTP.get(:active, server) == :disable
  end
end
