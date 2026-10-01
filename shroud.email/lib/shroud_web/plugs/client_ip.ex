defmodule ShroudWeb.Plugs.ClientIP do
  @moduledoc """
  Trusts X-Forwarded-For only from explicitly configured proxy IP addresses.
  The first untrusted hop, walking from the peer backwards, is the client.
  Private and loopback addresses are not implicitly trusted.
  """
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    %{conn | remote_ip: resolve(conn.remote_ip, conn.req_headers)}
  end

  def resolve(peer, headers) do
    peer = normalize(peer)
    proxies = Application.get_env(:shroud, :trusted_proxy_ips, [])

    with true <- peer in proxies,
         [header] <- for({"x-forwarded-for", value} <- headers, do: value),
         {:ok, addresses} <- parse_chain(header) do
      Enum.find(addresses, peer, &(&1 not in proxies))
    else
      _ -> peer
    end
  end

  defp parse_chain(header) do
    header
    |> String.split(",")
    |> Enum.reduce_while({:ok, []}, fn address, {:ok, addresses} ->
      case :inet.parse_strict_address(address |> String.trim() |> String.to_charlist()) do
        {:ok, ip} -> {:cont, {:ok, [normalize(ip) | addresses]}}
        {:error, _} -> {:halt, :error}
      end
    end)
  end

  def normalize({0, 0, 0, 0, 0, 65_535, high, low}) do
    {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}
  end

  def normalize(ip), do: ip
end
