defmodule Shroud.ProxyTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Proxy

  setup :verify_on_exit!

  describe "get/1" do
    test "successful cache miss" do
      url = "https://example.com/foo.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "foo"}}
      end)

      assert {:ok, "foo"} == Proxy.get(url)
    end

    test "invalid URL" do
      url = "https://example.com"

      assert {:error, :invalid_uri} == Proxy.get(url)
    end

    test "weird file type" do
      url = "https://example.com/foo.exe"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "foo"}}
      end)

      assert {:ok, "foo"} == Proxy.get(url)
    end

    test "non-200 response" do
      url = "https://example.com/foo.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 404}}
      end)

      assert {:error, :non_200_status_code} == Proxy.get(url)
    end
  end
end
