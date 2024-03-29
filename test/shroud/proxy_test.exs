defmodule Shroud.ProxyTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Proxy

  setup :verify_on_exit!

  describe "get/1" do
    test "proxies a request" do
      url = "https://example.com/foo.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: image_body()}}
      end)

      assert {:ok, {image_body(), nil}} == Proxy.get(url)
    end

    test "returns content-type header" do
      url = "https://example.com/foo.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: image_body(),
           headers: [{"Content-Type", "image/png"}]
         }}
      end)

      assert {:ok, {image_body(), "image/png"}} == Proxy.get(url)
    end

    test "invalid URL" do
      url = "https://example.com"

      assert {:error, :invalid_uri} == Proxy.get(url)
    end

    test "weird file type" do
      url = "https://example.com/foo.exe"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: image_body()}}
      end)

      assert {:ok, {image_body(), nil}} == Proxy.get(url)
    end

    test "non-200 response" do
      url = "https://example.com/foo.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 404}}
      end)

      assert {:error, :non_200_status_code} == Proxy.get(url)
    end

    test "follows 301 redirect" do
      first_url = "https://example.com/foo.png"
      second_url = "https://example.com/bar.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^first_url ->
        {:ok, %HTTPoison.Response{status_code: 301, headers: [{"Location", second_url}]}}
      end)
      |> expect(:get, fn ^second_url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: image_body()}}
      end)

      assert {:ok, {image_body(), nil}} == Proxy.get(first_url)
    end

    test "follows 302 redirect" do
      first_url = "https://example.com/foo.png"
      second_url = "https://example.com/bar.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^first_url ->
        {:ok, %HTTPoison.Response{status_code: 302, headers: [{"Location", second_url}]}}
      end)
      |> expect(:get, fn ^second_url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: image_body()}}
      end)

      assert {:ok, {image_body(), nil}} == Proxy.get(first_url)
    end

    test "does not follow redirect loop" do
      # stub to always return a redirect
      Shroud.MockHTTPoison
      |> stub(:get, fn _url ->
        {:ok,
         %HTTPoison.Response{
           status_code: 301,
           headers: [{"Location", "https://example.com/redirect"}]
         }}
      end)

      assert {:error, :too_many_redirects} == Proxy.get("https://example.com/image.png")
    end

    test "does not proxy non-image files" do
      # even though the file extension is .png, we return the string "foo"
      url = "https://example.com/foo.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "foo"}}
      end)

      assert {:error, :not_an_image} == Proxy.get(url)
    end

    test "handles URLs with spaces" do
      url = "https://example.com/foo bar.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: image_body()}}
      end)

      assert {:ok, {image_body(), nil}} == Proxy.get(url)
    end
  end

  defp image_body do
    File.read!("test/support/data/motherofalldemos.jpg")
  end
end
