defmodule Shroud.Email.CSSImages do
  @moduledoc false

  # Tokenize before interpreting URLs: strings, comments and CSS escapes must
  # not be mistaken for syntax. Non-image declarations (notably font src) stay intact.
  @tokens ~r"""
  /\*.*?\*/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|(?:[-\w]|\\(?:[0-9a-fA-F]{1,6}\s?|[^\r\n]))+|\s+|.
  """sux
  @properties ~w(background background-image border-image border-image-source list-style list-style-image content cursor mask mask-image -webkit-mask -webkit-mask-image shape-outside fill stroke filter clip-path)

  def map(css, fun, acc) do
    tokens = Regex.scan(@tokens, css) |> List.flatten()
    {tokens, acc} = declarations(tokens, fun, acc, [])
    {IO.iodata_to_binary(tokens), acc}
  end

  defp declarations([], _fun, acc, out), do: {Enum.reverse(out), acc}

  defp declarations([token | rest], fun, acc, out) do
    {space, tail} = Enum.split_while(rest, &trivia?/1)
    property = token |> decode() |> String.downcase()

    case tail do
      [":" | value] when property in @properties ->
        {mapped, tail, acc} = value(value, fun, acc, [], [], true)
        declarations(tail, fun, acc, [mapped, ":", space, token | out])

      [":" | value] ->
        # Custom properties can supply images through var().
        if String.starts_with?(property, "--") do
          {mapped, tail, acc} = value(value, fun, acc, [], [], true)
          declarations(tail, fun, acc, [mapped, ":", space, token | out])
        else
          declarations(rest, fun, acc, [token | out])
        end

      _ ->
        declarations(rest, fun, acc, [token | out])
    end
  end

  defp value([], _fun, acc, out, _stack, _candidate), do: {Enum.reverse(out), [], acc}

  defp value([token | _] = tokens, _fun, acc, out, [], _candidate) when token in [";", "}"] do
    {Enum.reverse(out), tokens, acc}
  end

  defp value([")" | rest], fun, acc, out, stack, _candidate) do
    value(rest, fun, acc, [")" | out], Enum.drop(stack, 1), false)
  end

  defp value(["," | rest], fun, acc, out, stack, _candidate) do
    value(rest, fun, acc, ["," | out], stack, true)
  end

  defp value([token | rest], fun, acc, out, stack, candidate) do
    name = token |> decode() |> String.downcase()
    {space, tail} = Enum.split_while(rest, &trivia?/1)

    cond do
      name == "url" and match?(["(" | _], tail) ->
        ["(" | body] = tail
        empty = if stack == [], do: "none", else: "url(\"data:,\")"
        {replacement, tail, acc} = url(body, [token, space, "("], fun, acc, empty)
        value(tail, fun, acc, [replacement | out], stack, false)

      match?(["(" | _], tail) and Regex.match?(~r/^[-\w]+$/u, name) ->
        ["(" | tail] = tail
        value(tail, fun, acc, ["(", space, token | out], [name | stack], true)

      string_image?(token, stack, candidate) ->
        original = unquote_css(token)
        {url, acc} = fun.(original, acc)
        replacement = replacement(url, original, token, "url(\"data:,\")")
        value(rest, fun, acc, [replacement | out], stack, false)

      true ->
        value(rest, fun, acc, [token | out], stack, candidate and trivia?(token))
    end
  end

  defp url(tokens, open, fun, acc, empty) do
    {body, tail} = Enum.split_while(tokens, &(&1 != ")"))
    original = body |> Enum.reject(&comment?/1) |> Enum.join() |> String.trim() |> unquote_css()
    {url, acc} = fun.(original, acc)
    # CSS accepts an omitted closing parenthesis at end of input.
    mapped = replacement(url, original, [open, body, Enum.take(tail, 1)], empty)
    mapped = if url && url != original, do: ["url(", mapped, ")"], else: mapped
    {mapped, Enum.drop(tail, 1), acc}
  end

  defp replacement(nil, _original, _tokens, empty), do: empty
  defp replacement(url, url, tokens, _empty), do: tokens
  defp replacement(url, _original, _tokens, _empty), do: "\"#{escape(url)}\""

  defp string_image?(token, stack, candidate) do
    candidate and List.first(stack) in ["image", "image-set", "-webkit-image-set"] and
      quoted?(token)
  end

  defp trivia?(token), do: comment?(token) or String.trim(token) == ""
  defp comment?(token), do: String.starts_with?(token, "/*")
  defp quoted?(token), do: String.starts_with?(token, ["\"", "'"])

  defp unquote_css(text) do
    text = if quoted?(text), do: String.slice(text, 1, String.length(text) - 2), else: text
    decode(text)
  end

  defp decode(text) do
    text = String.replace(text, ~r/\\(?:\r\n|[\n\r\f])/, "")

    Regex.replace(~r/\\([0-9a-fA-F]{1,6})\s?|\\([^\r\n])/u, text, fn _, hex, char ->
      if hex == "" do
        char
      else
        codepoint = String.to_integer(hex, 16)

        if codepoint in 1..0x10FFFF and codepoint not in 0xD800..0xDFFF,
          do: <<codepoint::utf8>>,
          else: "�"
      end
    end)
  end

  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\a ")
    |> String.replace("\r", "\\d ")
  end
end
