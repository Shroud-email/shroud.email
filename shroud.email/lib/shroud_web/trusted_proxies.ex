defmodule ShroudWeb.TrustedProxies do
  @moduledoc "Refreshes a bounded, expiring proxy-address snapshot off the request path."
  use GenServer

  @refresh_interval :timer.seconds(30)
  @max_age :timer.minutes(1)
  @lookup_timeout :timer.seconds(5)
  @max_addresses 256

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def addresses(table \\ __MODULE__) do
    case :ets.lookup(table, :snapshot) do
      [{:snapshot, expires_at, addresses}] ->
        if System.monotonic_time(:millisecond) < expires_at, do: addresses, else: []

      [] ->
        []
    end
  rescue
    ArgumentError -> []
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    table = Keyword.get(opts, :name, __MODULE__)
    :ets.new(table, [:named_table, :protected, read_concurrency: true])
    :ets.insert(table, {:snapshot, System.monotonic_time(:millisecond), []})

    {:ok,
     %{
       table: table,
       hosts: Keyword.get(opts, :hosts),
       resolver: Keyword.get(opts, :resolver, &resolve/1),
       task: nil,
       timeout: nil,
       deadline: nil
     }, {:continue, :refresh}}
  end

  @impl true
  def handle_continue(:refresh, state), do: handle_info(:refresh, state)

  @impl true
  def handle_info(:refresh, %{task: nil} = state) do
    hosts = state.hosts || Application.get_env(:shroud, :trusted_proxy_hosts, [])

    task =
      Task.Supervisor.async_nolink(ShroudWeb.ProxyResolverTasks, fn -> state.resolver.(hosts) end)

    timeout = Process.send_after(self(), {:lookup_timeout, task.ref}, @lookup_timeout)

    {:noreply, %{state | task: task, timeout: timeout, deadline: now() + @lookup_timeout}}
  end

  def handle_info(:refresh, state), do: {:noreply, state}

  def handle_info({ref, addresses}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    addresses = if now() < state.deadline, do: addresses, else: []
    finish(state, addresses)
  end

  def handle_info({:lookup_timeout, ref}, %{task: %Task{ref: ref}} = state) do
    Task.shutdown(state.task, :brutal_kill)
    finish(state, [])
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state),
    do: finish(state, [])

  def handle_info({:lookup_timeout, _ref}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{task: %Task{} = task}), do: Task.shutdown(task, :brutal_kill)
  def terminate(_reason, _state), do: :ok

  defp finish(state, addresses) do
    Process.cancel_timer(state.timeout)
    addresses = addresses |> Enum.uniq() |> Enum.take(@max_addresses)
    :ets.insert(state.table, {:snapshot, now() + @max_age, addresses})
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, %{state | task: nil, timeout: nil, deadline: nil}}
  end

  defp resolve(hosts) do
    for host <- hosts,
        family <- [:inet, :inet6],
        {:ok, addresses} <- [:inet.getaddrs(String.to_charlist(host), family)],
        address <- addresses,
        do: address
  end

  defp now, do: System.monotonic_time(:millisecond)
end
