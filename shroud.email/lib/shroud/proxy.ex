defmodule Shroud.Proxy do
  require Logger

  @type proxy_error ::
          :invalid_uri
          | :network_error
          | :non_200_status_code
          | :too_many_redirects
          | :not_an_image

  @spec get(String.t()) :: {:ok, {any, String.t()}} | {:error, proxy_error}
  def get(url) do
    case URI.parse(url) do
      %URI{path: nil} ->
        {:error, :invalid_uri}

      %URI{path: _path} ->
        get_from_network(url)
    end
  end

  defp get_from_network(url, depth \\ 0)

  defp get_from_network(_url, depth) when depth > 10 do
    {:error, :too_many_redirects}
  end

  defp get_from_network(url, depth) do
    case http().get(url) do
      {:ok, %HTTPoison.Response{status_code: status, headers: headers}}
      when status in [301, 302] ->
        case header_value(headers, "location") do
          nil ->
            {:error, :non_200_status_code}

          location ->
            get_from_network(location, depth + 1)
        end

      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}} ->
        if ExImageInfo.seems?(body) do
          {:ok, {body, header_value(headers, "content-type")}}
        else
          {:error, :not_an_image}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.notice("Attempt to proxy \"#{url}\" failed; returned status code #{status_code}")
        {:error, :non_200_status_code}

      {:error, %HTTPoison.Error{} = error} ->
        Logger.warning("Could not fetch #{url}: #{Exception.message(error)}")
        {:error, :network_error}
    end
  end

  defp header_value(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  defp http, do: Application.fetch_env!(:shroud, :http_client)
end
