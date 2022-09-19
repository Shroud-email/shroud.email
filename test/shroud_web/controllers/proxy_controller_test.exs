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
  end

  defp image_body do
    File.read!("test/support/data/motherofalldemos.jpg")
  end
end
