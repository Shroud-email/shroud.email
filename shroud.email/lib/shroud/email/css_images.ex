defmodule Shroud.Email.CSSImages do
  @moduledoc false

  alias Shroud.Email.CSSParser

  def map(css, fun, acc, inline \\ false) do
    case CSSParser.references(css, inline) do
      {:ok, references} ->
        {parts, cursor, acc} =
          Enum.reduce(references, {[], 0, acc}, fn [start, stop, original, nested],
                                                   {parts, cursor, acc} ->
            {url, acc} = fun.(original, acc)

            replacement =
              cond do
                url == original -> binary_part(css, start, stop - start)
                is_nil(url) and not nested -> "none"
                is_nil(url) -> "url(\"data:,\")"
                true -> "url(\"#{escape(url)}\")"
              end

            {[parts, binary_part(css, cursor, start - cursor), replacement], stop, acc}
          end)

        {IO.iodata_to_binary([parts, binary_part(css, cursor, byte_size(css) - cursor)]), acc}

      {:error, _reason} ->
        throw(:image_parse_failed)
    end
  end

  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\a ")
    |> String.replace("\r", "\\d ")
    |> String.replace("\f", "\\c ")
  end
end
