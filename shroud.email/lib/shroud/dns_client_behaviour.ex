defmodule Shroud.DnsClientBehaviour do
  @type record_type :: :txt | :cname | :mx | :a | :aaaa
  @callback lookup(String.t(), record_type) :: list()
end
