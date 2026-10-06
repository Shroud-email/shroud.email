defmodule Shroud.Email.ImageFetcherTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo

  import Mox
  alias Shroud.Email.{ImageFetcher, ParsedEmail}

  setup :verify_on_exit!
  setup {Req.Test, :verify_on_exit!}

  setup do
    test_pid = self()

    Req.Test.stub(ImageFetcher, fn conn ->
      send(test_pid, :unexpected_fetch)
      Plug.Conn.send_resp(conn, 500, "Unexpected fetch")
    end)

    :ok
  end

  test "enqueues distinct original image sources, including pixels, but not embedded images or links" do
    html = """
    <img src="https://images.example.com/photo.jpg">
    <img src="https://spy.example.com/open?id=123&amp;recipient=abc" width="1" height="1">
    <img src="https://images.example.com/photo.jpg">
    <img src="http://images.example.com">
    <img src="cid:attachment"><img src="data:image/png;base64,abc">
    <img src="/relative.jpg"><img><img src="file:///etc/passwd">
    <a href="https://example.com/unsubscribe">Unsubscribe</a>
    """

    email = %ParsedEmail{parsed_html: Floki.parse_document!(html)}

    assert :ok = ImageFetcher.enqueue(email)
    urls = all_enqueued(worker: ImageFetcher) |> Enum.map(& &1.args["url"]) |> Enum.sort()

    assert urls == [
             "http://images.example.com",
             "https://images.example.com/photo.jpg",
             "https://spy.example.com/open?id=123&recipient=abc"
           ]
  end

  test "enqueues fifty image jobs with a single bulk insert" do
    ref = make_ref()
    owner = self()

    :ok =
      :telemetry.attach(
        ref,
        [:shroud, :repo, :query],
        fn _, _, metadata, _ ->
          if self() == owner and String.starts_with?(metadata.query, "INSERT") and
               String.contains?(metadata.query, "oban_jobs") do
            send(owner, {ref, :insert})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(ref) end)

    html = Enum.map_join(1..50, fn n -> ~s(<img src="https://images.example.com/#{n}.jpg">) end)
    email = %ParsedEmail{parsed_html: Floki.parse_document!(html)}

    assert :ok = ImageFetcher.enqueue(email)
    assert_received {^ref, :insert}
    refute_received {^ref, :insert}
    urls = all_enqueued(worker: ImageFetcher) |> Enum.map(& &1.args["url"]) |> Enum.sort()
    expected = Enum.map(1..50, &"https://images.example.com/#{&1}.jpg") |> Enum.sort()
    assert urls == expected
  end

  test "text-only emails enqueue nothing" do
    assert :ok = ImageFetcher.enqueue(%ParsedEmail{parsed_html: nil})
    refute_enqueued(worker: ImageFetcher)
  end

  test "fetches the checked address with the original Host header and query" do
    test_pid = self()
    expect(Shroud.MockDnsClient, :lookup, fn "images.example.com", :a -> [{93, 184, 215, 14}] end)
    expect(Shroud.MockDnsClient, :lookup, fn "images.example.com", :aaaa -> [] end)

    Req.Test.expect(ImageFetcher, fn conn ->
      assert conn.method == "GET"
      assert conn.host == "93.184.215.14"
      assert conn.port == 8443
      assert conn.request_path == "/open"
      assert conn.query_string == "id=123&recipient=abc"
      assert Plug.Conn.get_req_header(conn, "host") == ["images.example.com:8443"]
      send(test_pid, :request_verified)
      Plug.Conn.send_resp(conn, 200, "not necessarily an image")
    end)

    assert :ok =
             perform_job(ImageFetcher, %{
               url: "https://images.example.com:8443/open?id=123&recipient=abc"
             })

    assert_received :request_verified
  end

  test "follows relative redirects and limits redirect loops" do
    test_pid = self()

    Req.Test.expect(ImageFetcher, 6, fn conn ->
      send(test_pid, {:visited, conn.request_path})
      conn |> Plug.Conn.put_resp_header("location", "next") |> Plug.Conn.send_resp(302, "")
    end)

    assert :ok = perform_job(ImageFetcher, %{url: "https://93.184.215.14/start"})
    assert_received {:visited, "/start"}
    for _ <- 1..5, do: assert_received({:visited, "/next"})
    refute_received {:visited, _}
    refute_received :unexpected_fetch
  end

  test "preserves TLS hostname, bounds timeouts and discards streamed bodies at the size limit" do
    test_pid = self()
    options = Application.fetch_env!(:shroud, :image_req_options)
    on_exit(fn -> Application.put_env(:shroud, :image_req_options, options) end)

    expect(Shroud.MockDnsClient, :lookup, fn "images.example.com", :a -> [{93, 184, 215, 14}] end)
    expect(Shroud.MockDnsClient, :lookup, fn "images.example.com", :aaaa -> [] end)

    Application.put_env(:shroud, :image_req_options,
      adapter: fn request ->
        assert request.url.host == "93.184.215.14"
        assert request.options.connect_options == [hostname: "images.example.com", timeout: 5_000]
        assert request.options.receive_timeout == 5_000
        assert request.options.redirect == false
        assert request.options.retry == false

        response = Req.Response.new(status: 200, body: "")
        chunk = :binary.copy(<<0>>, 5 * 1024 * 1024)
        assert {:cont, {request, response}} = request.into.({:data, chunk}, {request, response})
        assert response.body == ""
        assert {:halt, {request, response}} = request.into.({:data, <<0>>}, {request, response})
        assert response.body == ""
        send(test_pid, :stream_verified)
        {request, response}
      end
    )

    assert :ok = perform_job(ImageFetcher, %{url: "https://images.example.com/photo.jpg"})
    assert_received :stream_verified
    assert ImageFetcher.timeout(%Oban.Job{}) == 30_000
  end

  test "blocks private, local, reserved and non-HTTP destinations without making requests" do
    for url <- [
          "http://127.0.0.1/admin",
          "http://10.0.0.1/",
          "http://172.16.0.1/",
          "http://192.168.1.1/",
          "http://169.254.169.254/latest/meta-data/",
          "http://100.64.0.1/",
          "http://0.0.0.0/",
          "http://224.0.0.1/",
          "http://239.255.255.255/",
          "http://240.0.0.1/",
          "http://255.255.255.255/",
          "http://192.0.2.1/",
          "http://198.51.100.1/",
          "http://203.0.113.1/",
          "http://198.18.0.1/",
          "http://192.88.99.1/",
          "http://192.31.196.1/",
          "http://[::1]/",
          "http://[::ffff:127.0.0.1]/",
          "http://[::ffff:8.8.8.8]/",
          "http://[::8.8.8.8]/",
          "http://[64:ff9b::808:808]/",
          "http://[fc00::1]/",
          "http://[fe80::1]/",
          "http://[ff02::1]/",
          "http://[2001::1]/",
          "http://[2001:db8::1]/",
          "http://[2002:7f00:1::]/",
          "http://[3fff::1]/",
          "http://[4000::1]/",
          "file:///etc/passwd",
          "ftp://example.com/image",
          "/relative",
          "",
          "http://user:password@93.184.215.14/"
        ] do
      assert :ok = perform_job(ImageFetcher, %{url: url})
    end

    refute_received :unexpected_fetch
  end

  test "allows ordinary public IPv4 and IPv6 unicast addresses" do
    for {url, expected_host} <- [
          {"https://8.8.8.8/image", "8.8.8.8"},
          {"https://172.15.255.255/image", "172.15.255.255"},
          {"https://172.32.0.1/image", "172.32.0.1"},
          {"https://223.255.255.254/image", "223.255.255.254"},
          {"https://[2606:4700:4700::1111]/image", "2606:4700:4700::1111"},
          {"https://[2001:4860:4860::8888]/image", "2001:4860:4860::8888"}
        ] do
      Req.Test.expect(ImageFetcher, fn conn ->
        assert conn.host == expected_host
        Plug.Conn.send_resp(conn, 200, "Image")
      end)

      assert :ok = perform_job(ImageFetcher, %{url: url})
    end

    refute_received :unexpected_fetch
  end

  test "pins an IPv6-only DNS destination while preserving the original Host header" do
    expect(Shroud.MockDnsClient, :lookup, fn "images.example.com", :a -> [] end)

    expect(Shroud.MockDnsClient, :lookup, fn "images.example.com", :aaaa ->
      [{0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111}]
    end)

    Req.Test.expect(ImageFetcher, fn conn ->
      assert conn.host == "2606:4700:4700::1111"
      assert Plug.Conn.get_req_header(conn, "host") == ["images.example.com"]
      Plug.Conn.send_resp(conn, 200, "Image")
    end)

    assert :ok = perform_job(ImageFetcher, %{url: "https://images.example.com/image"})
    refute_received :unexpected_fetch
  end

  test "rejects a hostname if any DNS answer is private" do
    expect(Shroud.MockDnsClient, :lookup, fn "mixed.example.com", :a ->
      [{93, 184, 215, 14}, {10, 0, 0, 1}]
    end)

    expect(Shroud.MockDnsClient, :lookup, fn "mixed.example.com", :aaaa -> [] end)
    assert :ok = perform_job(ImageFetcher, %{url: "http://mixed.example.com/pixel"})
    refute_received :unexpected_fetch
  end

  test "rechecks redirected destinations and never contacts private targets" do
    Req.Test.expect(ImageFetcher, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "http://169.254.169.254/latest/meta-data/")
      |> Plug.Conn.send_resp(302, "")
    end)

    assert :ok = perform_job(ImageFetcher, %{url: "https://93.184.215.14/pixel"})
    refute_received :unexpected_fetch
  end

  test "image jobs execute independently when another image fails" do
    test_pid = self()
    Req.Test.expect(ImageFetcher, fn conn -> Req.Test.transport_error(conn, :timeout) end)

    Req.Test.expect(ImageFetcher, fn conn ->
      send(test_pid, {:visited, conn.request_path})
      Plug.Conn.send_resp(conn, 200, "Image")
    end)

    html = ~s(<img src="https://93.184.215.14/failed"><img src="https://93.184.215.14/success">)
    assert :ok = ImageFetcher.enqueue(%ParsedEmail{parsed_html: Floki.parse_document!(html)})
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :image_fetcher)

    assert_received {:visited, "/success"}
    refute_received :unexpected_fetch
  end

  test "HTTP errors and network failures are best-effort and do not retry" do
    Req.Test.expect(ImageFetcher, fn conn -> Plug.Conn.send_resp(conn, 503, "Unavailable") end)
    assert :ok = perform_job(ImageFetcher, %{url: "https://93.184.215.14/pixel"})

    Req.Test.expect(ImageFetcher, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert :ok = perform_job(ImageFetcher, %{url: "https://93.184.215.14/pixel"})
  end
end
