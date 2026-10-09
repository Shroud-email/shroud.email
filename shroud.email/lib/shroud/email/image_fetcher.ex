defmodule Shroud.Email.ImageFetcher do
  @moduledoc """
  Visits remote images independently of email delivery and recipient activity.
  Image bodies are discarded. Only public HTTP(S) destinations are contacted.
  Each email queues at most 500 distinct eligible image URLs, in document order.
  """

  use Oban.Worker, queue: :image_fetcher, max_attempts: 1

  alias Shroud.Email.{ImageSources, ParsedEmail}

  @max_bytes 5 * 1024 * 1024
  @max_images 500

  @spec enqueue(ParsedEmail.t()) :: :ok
  def enqueue(%ParsedEmail{parsed_html: nil}), do: :ok

  def enqueue(%ParsedEmail{parsed_html: html}) do
    html
    |> ImageSources.urls()
    |> Stream.uniq()
    |> Stream.filter(&(remote_uri(&1) != nil))
    |> Stream.take(@max_images)
    |> Enum.map(&new(%{url: &1}))
    |> Oban.insert_all()

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"url" => url}}) do
    visit(url, 0)
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: 30_000

  defp visit(_url, depth) when depth > 5, do: :ok

  defp visit(url, depth) do
    with %URI{} = uri <- remote_uri(url),
         {:ok, address} <- public_address(uri.host),
         {:ok, response} <- fetch(uri, address) do
      if response.status in [301, 302, 303, 307, 308] do
        case Req.Response.get_header(response, "location") do
          [location | _] -> visit(URI.merge(uri, location) |> URI.to_string(), depth + 1)
          [] -> :ok
        end
      end
    end
  end

  defp remote_uri(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        uri

      _ ->
        nil
    end
  end

  defp public_address(host) do
    addresses =
      case :inet.parse_address(to_charlist(host)) do
        {:ok, address} ->
          [address]

        {:error, _} ->
          dns = Application.get_env(:shroud, :dns_client, Shroud.DnsClient)
          dns.lookup(host, :a) ++ dns.lookup(host, :aaaa)
      end

    case addresses do
      [address | _] ->
        if Enum.all?(addresses, &public_address?/1), do: {:ok, address}, else: :error

      [] ->
        :error
    end
  end

  defp public_address?(address) do
    prefix = Pfx.new(address)

    # Only ordinary unicast destinations are allowed. Deny every IANA special
    # range, even globally reachable ones, and limit IPv6 to global unicast.
    (prefix.maxlen == 32 or Pfx.member?(prefix, "2000::/3")) and
      not Pfx.multicast?(prefix) and is_nil(Pfx.iana_special(prefix))
  end

  defp fetch(uri, address) do
    # Pin the connection to the checked IP to prevent DNS rebinding. Preserve
    # the original Host header and TLS hostname for virtual hosts and certificates.
    host = URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port})
    host = String.replace_prefix(host, uri.scheme <> "://", "")
    pinned = %{uri | host: address |> :inet.ntoa() |> to_string(), authority: nil}

    options = [
      url: URI.to_string(pinned),
      headers: [{"host", host}],
      connect_options: [hostname: uri.host, timeout: 5_000],
      receive_timeout: 5_000,
      redirect: false,
      retry: false,
      decode_body: false,
      compressed: false,
      into: fn {:data, bytes}, {request, response} ->
        size = Map.get(response.private, :image_bytes, 0) + byte_size(bytes)
        response = Req.Response.put_private(response, :image_bytes, size)
        action = if size > @max_bytes, do: :halt, else: :cont
        {action, {request, response}}
      end
    ]

    options
    |> Keyword.merge(Application.get_env(:shroud, :image_req_options, []))
    |> Req.get()
  end
end
