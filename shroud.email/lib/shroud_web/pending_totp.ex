defmodule ShroudWeb.PendingTOTP do
  @moduledoc "Stores pending TOTP settings for a login session for up to 30 minutes."
  use GenServer

  @ttl :timer.minutes(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def get(key, server \\ __MODULE__), do: GenServer.call(server, {:get, key})
  def put(key, pending, server \\ __MODULE__), do: GenServer.call(server, {:put, key, pending})
  def delete(key, server \\ __MODULE__), do: GenServer.call(server, {:delete, key})

  @impl true
  def init(state) do
    Process.send_after(self(), :expire, @ttl)
    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case state[key] do
      {expires_at, pending} ->
        if expires_at > now() do
          {:reply, pending, state}
        else
          {:reply, nil, Map.delete(state, key)}
        end

      nil ->
        {:reply, nil, state}
    end
  end

  def handle_call({:put, key, pending}, _from, state) do
    {:reply, :ok, Map.put(state, key, {now() + @ttl, pending})}
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, Map.delete(state, key)}
  end

  @impl true
  def handle_info(:expire, state) do
    now = now()
    state = Map.reject(state, fn {_key, {expires_at, _pending}} -> expires_at <= now end)
    Process.send_after(self(), :expire, @ttl)
    {:noreply, state}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
