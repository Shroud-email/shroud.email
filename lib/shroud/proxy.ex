defmodule Shroud.Proxy do
  require Logger

  @type proxy_error :: :invalid_uri | :disallowed_filetype | :non_200_status_code | any

  @spec get(String.t()) :: {:ok, any} | {:error, proxy_error}
  def get(url) do
    case URI.parse(url) do
      %URI{path: nil} ->
        {:error, :invalid_uri}

      %URI{path: path} ->
        mime_type = MIME.from_path(path)

        if allowed_mime_type?(mime_type) do
          get_from_network(url)
        else
          {:error, :disallowed_filetype}
        end
    end
  end

  defp get_from_network(url) do
    case http().get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.info("Attempt to proxy \"#{url}\" failed; returned status code #{status_code}")
        {:error, :non_200_status_code}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warn("Could not fetch #{url}: #{reason}")
        {:error, reason}
    end
  end

  defp allowed_mime_type?(mime_type) do
    String.starts_with?(mime_type, "image")
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
