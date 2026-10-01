defmodule ShroudWeb.TrustedProxiesTest do
  use ExUnit.Case, async: true
  alias ShroudWeb.TrustedProxies

  test "DNS runs in the background and only one lookup can be in flight" do
    cache = start_cache()
    assert_receive {:lookup, worker, ["caddy"]}
    assert TrustedProxies.addresses(__MODULE__) == []

    for _ <- 1..10, do: send(cache, :refresh)
    _ = :sys.get_state(cache)
    refute_receive {:lookup, _, _}
    assert TrustedProxies.addresses(__MODULE__) == []

    finish_lookup(cache, worker, [{172, 18, 0, 7}])
    assert TrustedProxies.addresses(__MODULE__) == [{172, 18, 0, 7}]
  end

  test "missing and expired snapshots grant no trust, and refresh replaces old addresses" do
    assert TrustedProxies.addresses(:missing_proxy_snapshot) == []
    cache = start_cache()
    assert_receive {:lookup, worker, _}
    finish_lookup(cache, worker, [{172, 18, 0, 7}])

    :sys.replace_state(cache, fn state ->
      :ets.insert(__MODULE__, {:snapshot, System.monotonic_time(:millisecond), [{172, 18, 0, 7}]})
      state
    end)

    assert TrustedProxies.addresses(__MODULE__) == []
    send(cache, :refresh)
    assert_receive {:lookup, replacement, _}
    assert TrustedProxies.addresses(__MODULE__) == []
    finish_lookup(cache, replacement, [{172, 18, 0, 9}])
    assert TrustedProxies.addresses(__MODULE__) == [{172, 18, 0, 9}]
  end

  test "lookup timeout kills the worker, clears trust, and allows recovery" do
    cache = start_cache()
    assert_receive {:lookup, worker, _}
    finish_lookup(cache, worker, [{172, 18, 0, 7}])
    send(cache, :refresh)
    assert_receive {:lookup, blocked, _}
    state = :sys.get_state(cache)
    assert Process.read_timer(state.timeout) in 1..5_000
    ref = Process.monitor(blocked)
    send(cache, {:lookup_timeout, state.task.ref})
    _ = :sys.get_state(cache)
    assert_receive {:DOWN, ^ref, :process, ^blocked, :killed}
    assert TrustedProxies.addresses(__MODULE__) == []

    send(cache, :refresh)
    assert_receive {:lookup, recovered, _}
    finish_lookup(cache, recovered, [{172, 18, 0, 9}])
    assert TrustedProxies.addresses(__MODULE__) == [{172, 18, 0, 9}]
  end

  test "results arriving beyond the lookup deadline are discarded" do
    cache = start_cache()
    assert_receive {:lookup, worker, _}
    :sys.replace_state(cache, &%{&1 | deadline: System.monotonic_time(:millisecond) - 1})
    finish_lookup(cache, worker, [{172, 18, 0, 7}])
    assert TrustedProxies.addresses(__MODULE__) == []
  end

  test "failed refresh clears a previously trusted snapshot" do
    cache = start_cache()
    assert_receive {:lookup, worker, _}
    finish_lookup(cache, worker, [{172, 18, 0, 7}])
    send(cache, :refresh)
    assert_receive {:lookup, failed, _}
    finish_lookup(cache, failed, [])
    assert TrustedProxies.addresses(__MODULE__) == []
  end

  test "snapshots are deduplicated and bounded" do
    cache = start_cache()
    assert_receive {:lookup, worker, _}
    addresses = for n <- 0..256, do: {192, 0, div(n, 256), rem(n, 256)}
    finish_lookup(cache, worker, [hd(addresses) | addresses])
    assert TrustedProxies.addresses(__MODULE__) == Enum.take(addresses, 256)
  end

  test "resolver crashes clear trust without crashing the cache" do
    cache = start_cache()
    assert_receive {:lookup, worker, _}
    finish_lookup(cache, worker, [{172, 18, 0, 7}])
    send(cache, :refresh)
    assert_receive {:lookup, failed, _}
    ref = Process.monitor(failed)
    Process.exit(failed, :kill)
    assert_receive {:DOWN, ^ref, :process, ^failed, :killed}
    assert %{task: nil} = :sys.get_state(cache)
    assert TrustedProxies.addresses(__MODULE__) == []
  end

  test "stopping the cache cancels its lookup and removes the snapshot" do
    start_cache()
    assert_receive {:lookup, worker, _}
    ref = Process.monitor(worker)
    stop_supervised!(TrustedProxies)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    assert TrustedProxies.addresses(__MODULE__) == []
  end

  test "the default resolver resolves configured hostnames off the caller process" do
    cache = start_supervised!({TrustedProxies, name: __MODULE__, hosts: ["localhost"]})
    await_lookup(cache)
    assert {127, 0, 0, 1} in TrustedProxies.addresses(__MODULE__)
  end

  defp start_cache do
    parent = self()

    start_supervised!(
      {TrustedProxies,
       name: __MODULE__,
       hosts: ["caddy"],
       resolver: fn hosts ->
         send(parent, {:lookup, self(), hosts})

         receive do
           {:addresses, addresses} -> addresses
         end
       end}
    )
  end

  defp finish_lookup(cache, worker, addresses) do
    ref = Process.monitor(worker)
    send(worker, {:addresses, addresses})
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    assert %{task: nil} = :sys.get_state(cache)
  end

  defp await_lookup(cache) do
    case :sys.get_state(cache).task do
      nil ->
        :ok

      %Task{pid: worker} ->
        ref = Process.monitor(worker)
        assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1_000
        assert %{task: nil} = :sys.get_state(cache)
    end
  end
end
