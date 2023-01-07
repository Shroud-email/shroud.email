defmodule ShroudWeb.ProxyControllerTest do
  use ShroudWeb.ConnCase, async: true
  import Mox

  setup :verify_on_exit!

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, ShroudWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn}
  end

  describe "GET /proxy" do
    test "converts URL-encoded spaces", %{conn: conn} do
      url = "https://example.com/foo bar.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok, %HTTPoison.Response{status_code: 200, body: image_body()}}
      end)

      conn = get(conn, Routes.proxy_path(conn, :proxy, %{"url" => url}))

      assert response_content_type(conn, :png)
    end

    test "handles URLs in query string", %{conn: conn} do
      url = "https://cdn.com/image?url=https%3A%2F%2Fexample%2Ecom%2Ffoo%2Epng"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: image_body(),
           headers: [{"Content-Type", "image/png"}]
         }}
      end)

      conn = get(conn, Routes.proxy_path(conn, :proxy), %{"url" => url})

      assert response_content_type(conn, :png)
    end

    test "this one", %{conn: conn} do
      url =
        "https://simons.cheetah-reach.com/nci/2786/en/3e25229d9aa0c8d4553bd0a4c535c783/12/0.png"

      Shroud.MockHTTPoison
      |> expect(:get, fn ^url ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: image_body(),
           headers: [{"Content-Type", "image/png"}]
         }}
      end)

      conn = get(conn, Routes.proxy_path(conn, :proxy), %{"url" => url})

      assert response_content_type(conn, :png)
    end
  end

  defp image_body do
    File.read!("test/support/data/motherofalldemos.jpg")
  end
end
