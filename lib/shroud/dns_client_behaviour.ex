defmodule Shroud.DnsClientBehaviour do
  @type record_type :: :txt | :cname | :mx
  @callback lookup(String.t(), record_type) :: list()
end
