defmodule Shroud.Email.ConditionalImages do
  @moduledoc false

  # Outlook wrappers can open in one conditional comment and close in another.
  # Keep source spans intact; a DOM serializer would repair those partial trees.
  @markup ~r"""
  <!--.*?-->|<(?<raw>style|script|textarea|title|xmp)\b(?:[^"'<>]|"[^"]*"|'[^']*')*>.*?</\k<raw>\s*>|<(?:[^"'<>]|"[^"]*"|'[^']*')*>|[^<]+|<
  """isux
  @attributes ~r/\s+([^\s=<>\/]+)\s*=\s*("[^"]*"|'[^']*'|[^\s<>]+)/u
  @leaf_tags ~w(area base br col embed hr img input link meta param source track wbr style script textarea title xmp)

  def map(html, attributes, css, acc) do
    {parts, {acc, _stack}} =
      @markup
      |> Regex.scan(html, capture: :first)
      |> Enum.map_reduce({acc, []}, fn [text], {acc, stack} ->
        {mapped, acc} = part(text, attributes, css, acc, List.first(stack))
        {mapped, {acc, parents(text, stack)}}
      end)

    {IO.iodata_to_binary(parts), acc}
  end

  defp part("<!--" <> _ = text, _attributes, _css, acc, _parent), do: {text, acc}

  defp part(text, attributes, css, acc, parent) do
    case Regex.run(~r/\A(<style\b(?:[^"'<>]|"[^"]*"|'[^']*')*>)(.*)(<\/style\s*>)\z/is, text) do
      [_, opening, body, closing] ->
        {opening, acc} = tag(opening, attributes, acc, parent)
        {body, acc} = css.(body, acc)
        {[opening, body, closing], acc}

      _ ->
        if Regex.match?(~r/\A<(script|textarea|title|xmp)\b/i, text) do
          {text, acc}
        else
          tag(text, attributes, acc, parent)
        end
    end
  end

  defp tag(text, attributes, acc, parent) do
    # Only a single opening tag is parsed for decoded attribute values. Its
    # children and repaired closing tags are never used to generate output.
    case Regex.run(~r/\A<([a-z][\w:.-]*)\b/is, text) do
      [_, name] ->
        case Floki.parse_fragment(text) do
          {:ok, [{_tag, attrs, _children} | _]} ->
            {mapped, acc} = attributes.(String.downcase(name), parent, attrs, acc)
            {rewrite(text, attrs, Enum.reject(mapped, &is_nil/1)), acc}

          _ ->
            {text, acc}
        end

      _ ->
        {text, acc}
    end
  end

  defp parents(text, stack) do
    case Regex.run(~r/\A<(\/?)([a-z][\w:.-]*)\b/i, text) do
      [_, closing, name] ->
        name = String.downcase(name)

        cond do
          closing == "/" ->
            case Enum.drop_while(stack, &(&1 != name)) do
              [_ | rest] -> rest
              [] -> stack
            end

          name in @leaf_tags or String.ends_with?(text, "/>") ->
            stack

          true ->
            [name | stack]
        end

      _ ->
        stack
    end
  end

  defp rewrite(text, attrs, mapped) do
    {parts, cursor} =
      @attributes
      |> Regex.scan(text, return: :index)
      |> Enum.reduce({[], 0}, fn [{start, length}, name_span, {value_start, value_length}],
                                 {parts, cursor} ->
        name = text |> span(name_span) |> String.downcase()
        original = List.keyfind(attrs, name, 0)
        replacement = List.keyfind(mapped, name, 0)
        raw = binary_part(text, start, length)
        raw_value = binary_part(text, value_start, value_length)

        changed =
          case {original, replacement} do
            {same, same} ->
              raw

            {_, nil} ->
              ""

            {_, {_, value}} ->
              prefix = binary_part(text, start, value_start - start)
              quote = if String.starts_with?(raw_value, "'"), do: "'", else: "\""
              [prefix, quote, Plug.HTML.html_escape(value), quote]
          end

        gap = binary_part(text, cursor, start - cursor)
        {[parts, gap, changed], start + length}
      end)

    [parts, binary_part(text, cursor, byte_size(text) - cursor)]
  end

  defp span(text, {start, length}), do: binary_part(text, start, length)
end
