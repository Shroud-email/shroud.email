defmodule ShroudWeb.ProxyController do
  use ShroudWeb, :controller
  alias Shroud.Proxy

  def proxy(conn, %{"url" => url}) do
    case Proxy.get(url) do
      {:ok, {data, content_type}} ->
        mime_type = if content_type, do: content_type, else: guess_mime_type(url)

        conn
        |> put_resp_content_type(mime_type)
        |> send_resp(200, data)

      {:error, error} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "Error: " <> Atom.to_string(error))
    end
  end

  defp guess_mime_type(url) do
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
end
