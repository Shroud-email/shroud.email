defmodule Shroud.DnsClient do
  @behaviour Shroud.DnsClientBehaviour

  @impl true
  def lookup(domain, record_type) do
    domain
    |> to_charlist()
    |> :inet_res.lookup(:in, record_type)
    |> Enum.map(fn record ->
      if is_list(record) and length(record) == 1, do: hd(record), else: record
    end)
  end
end
