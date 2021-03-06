defmodule ShroudWeb.ProxyController do
  use ShroudWeb, :controller
  alias Shroud.Proxy

  plug :set_appsignal_namespace

  def proxy(conn, %{"url" => url}) do
    case Proxy.get(url) do
      {:ok, data} ->
        mime_type = get_mime_type(url)

        conn
        |> put_resp_content_type(mime_type)
        |> send_resp(200, data)

      {:error, error} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "Error: " <> Atom.to_string(error))
    end
  end

  defp get_mime_type(url) do
    %{path: image_path} =
      url
      |> URI.decode()
      |> URI.parse()

    if is_nil(image_path) do
      nil
    else
      MIME.from_path(image_path)
    end
  end

  # Proxy requests are often much slower than other requests due to upstream servers,
  # so separate them out in AppSignal so we can accurately monitor our app's performance
  defp set_appsignal_namespace(conn, _params) do
    Appsignal.Span.set_namespace(Appsignal.Tracer.root_span(), "proxy")
    conn
  end
end
