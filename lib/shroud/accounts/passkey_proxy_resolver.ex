defmodule Shroud.Accounts.PasskeyProxyResolver do
  use GenServer

  @refresh_interval :timer.seconds(30)
  @retry_interval :timer.seconds(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    Application.put_env(:shroud, :passkey_resolved_proxy_ips, [])
    send(self(), :refresh)
    {:ok, nil}
  end

  @impl true
  def handle_info(:refresh, state) do
    hosts = Application.get_env(:shroud, :passkey_trusted_proxy_hosts, [])

    addresses =
      for host <- hosts,
          family <- [:inet, :inet6],
          {:ok, ips} <- [:inet.getaddrs(String.to_charlist(host), family)],
          ip <- ips,
          uniq: true,
          do: ip

    Application.put_env(:shroud, :passkey_resolved_proxy_ips, addresses)
    delay = if hosts != [] and addresses == [], do: @retry_interval, else: @refresh_interval
    Process.send_after(self(), :refresh, delay)
    {:noreply, state}
  end
end
