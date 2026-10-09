defmodule Shroud.Email.ImageSources do
  @moduledoc """
  Finds and rewrites image references without following links or external stylesheets.
  Embedded data and attachment URLs are preserved. Scheme-relative URLs use HTTPS.
  """

  alias Shroud.Email.{ConditionalImages, CSSImages}

  def urls(html) do
    {_, urls} = map(html, fn url, _attrs, acc -> {url, [url | acc]} end, [])
    Enum.reverse(urls)
  end

  def map(html, fun, acc, parent \\ nil) when is_list(html) do
    {html, acc} = Enum.map_reduce(html, acc, &node(&1, fun, &2, parent))
    {Enum.reject(html, &is_nil/1), acc}
  end

  def remote_url(source) do
    source = String.trim(source)
    source = if String.starts_with?(source, "//"), do: "https:" <> source, else: source

    case URI.parse(source) do
      %URI{scheme: scheme, host: host, userinfo: nil} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        %{
          uri
          | path: encode_component(uri.path),
            query: encode_component(uri.query),
            fragment: encode_component(uri.fragment)
        }
        |> URI.to_string()

      _ ->
        nil
    end
  end

  defp encode_component(nil), do: nil

  defp encode_component(value) do
    URI.encode(value, fn char ->
      char == ?% or (URI.char_unescaped?(char) and char not in [?[, ?]])
    end)
  end

  defp source(url, fun, acc) do
    case remote_url(url) do
      nil -> {url, acc}
      remote -> fun.(remote, acc)
    end
  end

  defp node({:comment, comment} = node, fun, acc, parent) do
    case Regex.run(~r/\A(\s*\[if\s[^\]]+\]>)([\s\S]*)(<!\[endif\]\s*)\z/i, comment) do
      [_, open, html, close] ->
        attributes = fn tag, inner_parent, attrs, acc ->
          Enum.map_reduce(
            attrs,
            acc,
            &attribute(&1, {tag, inner_parent || parent, attrs}, fun, &2)
          )
        end

        css = fn text, acc ->
          CSSImages.map(text, &source(&1, fn url, acc -> fun.(url, nil, acc) end, &2), acc)
        end

        {html, acc} = ConditionalImages.map(html, attributes, css, acc)
        {{:comment, open <> html <> close}, acc}

      _ ->
        {node, acc}
    end
  end

  defp node({tag, attrs, children}, fun, acc, parent) when is_binary(tag) do
    original_attrs = attrs
    css_fun = fn url, acc -> fun.(url, nil, acc) end

    {attrs, acc} =
      Enum.map_reduce(attrs, acc, &attribute(&1, {tag, parent, original_attrs}, fun, &2))

    {children, acc} =
      if tag == "style" do
        Enum.map_reduce(children, acc, fn
          text, acc when is_binary(text) -> CSSImages.map(text, &source(&1, css_fun, &2), acc)
          child, acc -> {child, acc}
        end)
      else
        map(children, fun, acc, tag)
      end

    attrs = Enum.reject(attrs, &is_nil/1)

    removed_image =
      tag == "img" and parent != "picture" and
        Enum.any?(original_attrs, fn {name, _} -> name in ["src", "srcset"] end) and
        not Enum.any?(attrs, fn {name, _} -> name in ["src", "srcset"] end)

    {if(not removed_image, do: {tag, attrs, children}), acc}
  end

  defp node(node, _fun, acc, _parent), do: {node, acc}

  defp attribute({"style", value}, _context, fun, acc) do
    css_fun = fn url, acc -> fun.(url, nil, acc) end
    {value, acc} = CSSImages.map(value, &source(&1, css_fun, &2), acc)
    {{"style", value}, acc}
  end

  defp attribute({"srcset", value}, {tag, parent, attrs}, fun, acc)
       when tag == "img" or (tag == "source" and parent == "picture") do
    image_fun = fn url, acc -> fun.(url, if(tag == "img", do: attrs), acc) end
    {value, acc} = srcset(value, image_fun, acc)
    {if(value != "", do: {"srcset", value}), acc}
  end

  defp attribute({name, value} = attr, {tag, _parent, attrs}, fun, acc) do
    if image_attribute?(tag, name) and
         (tag != "input" or
            String.downcase(List.keyfind(attrs, "type", 0, {"type", ""}) |> elem(1)) == "image") do
      image_fun = fn url, acc -> fun.(url, if(tag == "img", do: attrs), acc) end
      {value, acc} = source(value, image_fun, acc)
      {if(value, do: {name, value}), acc}
    else
      {attr, acc}
    end
  end

  defp image_attribute?(tag, "src"),
    do: tag in ["img", "v:fill", "v:imagedata", "v:image", "input"]

  defp image_attribute?(tag, "background"), do: tag in ["body", "table", "td", "th", "tr"]

  defp image_attribute?(tag, "poster"), do: tag == "video"

  defp image_attribute?(tag, name),
    do: tag in ["image", "feimage"] and name in ["href", "xlink:href"]

  # Follow srcset's URL/descriptor boundaries rather than splitting on commas:
  # commas inside URLs (especially data URLs) are not candidate separators.
  defp srcset(text, fun, acc) do
    {candidates, acc} = candidates(String.trim_leading(text), fun, acc, [])
    {Enum.reverse(candidates) |> Enum.join(", "), acc}
  end

  defp candidates("", _fun, acc, out), do: {out, acc}

  defp candidates("," <> rest, fun, acc, out),
    do: candidates(String.trim_leading(rest), fun, acc, out)

  defp candidates(text, fun, acc, out) do
    [url | rest] = String.split(text, ~r/\s+/, parts: 2)
    rest = List.first(rest) || ""

    {descriptor, rest} =
      if String.ends_with?(url, ",") do
        {"", rest}
      else
        case String.split(rest, ",", parts: 2) do
          [descriptor, rest] -> {descriptor, rest}
          [descriptor] -> {descriptor, ""}
        end
      end

    {url, acc} = source(String.trim_trailing(url, ","), fun, acc)
    out = if url, do: [String.trim(url <> " " <> descriptor) | out], else: out
    candidates(String.trim_leading(rest), fun, acc, out)
  end
end
