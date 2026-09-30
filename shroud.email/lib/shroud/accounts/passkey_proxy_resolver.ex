defmodule Shroud.Accounts.PasskeyProxyResolver do
  use GenServer
  require Logger

  @refresh_interval :timer.seconds(30)
  @retry_interval :timer.seconds(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def trusted?(peer, table \\ __MODULE__) do
    case :ets.lookup(table, :addresses) do
      [{:addresses, addresses}] -> peer in addresses
      [] -> false
    end
  rescue
    ArgumentError -> false
  end

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :table, __MODULE__)
    :ets.new(table, [:named_table, :protected, :set, read_concurrency: true])

    {:ok,
     refresh(%{
       table: table,
       hosts:
         Keyword.get(opts, :hosts, Application.get_env(:shroud, :passkey_trusted_proxy_hosts, []))
     })}
  end

  @impl true
  def handle_info(:refresh, state) do
    {:noreply, refresh(state)}
  end

  defp refresh(state) do
    addresses =
      for host <- state.hosts,
          family <- [:inet, :inet6],
          {:ok, ips} <- [:inet.getaddrs(String.to_charlist(host), family)],
          ip <- ips,
          uniq: true,
          do: ip

    :ets.insert(state.table, {:addresses, addresses})

    if state.hosts != [] and addresses == [] do
      Logger.warning(
        "Passkey trusted proxy hosts could not be resolved: #{Enum.join(state.hosts, ", ")}"
      )
    end

    delay = if state.hosts != [] and addresses == [], do: @retry_interval, else: @refresh_interval
    Process.send_after(self(), :refresh, delay)
    state
  end
end
