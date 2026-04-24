defmodule Shroud.Email.SpamEmailScrubber do
  @moduledoc """
  This is HtmlSanitizeEx's basic_html scrubber modified
  to also allow (scrubbed) CSS through.

  Used to sanitize the HTML body of spam emails before we store it.
  """

  require HtmlSanitizeEx.Scrubber.Meta
  alias HtmlSanitizeEx.Scrubber.CSS
  alias HtmlSanitizeEx.Scrubber.Meta

  @valid_schemes ["http", "https", "mailto"]

  # Removes any CDATA tags before the traverser/scrubber runs.
  Meta.remove_cdata_sections_before_scrub()

  Meta.strip_comments()

  Meta.allow_tag_with_uri_attributes("a", ["href"], @valid_schemes)
  Meta.allow_tag_with_these_attributes("a", ["name", "title"])

  Meta.allow_tag_with_these_attributes("b", [])
  Meta.allow_tag_with_these_attributes("blockquote", [])
  Meta.allow_tag_with_these_attributes("br", [])
  Meta.allow_tag_with_these_attributes("code", [])
  Meta.allow_tag_with_these_attributes("del", [])
  Meta.allow_tag_with_these_attributes("em", [])
  Meta.allow_tag_with_these_attributes("h1", [])
  Meta.allow_tag_with_these_attributes("h2", [])
  Meta.allow_tag_with_these_attributes("h3", [])
  Meta.allow_tag_with_these_attributes("h4", [])
  Meta.allow_tag_with_these_attributes("h5", [])
  Meta.allow_tag_with_these_attributes("h6", [])
  Meta.allow_tag_with_these_attributes("hr", [])
  Meta.allow_tag_with_these_attributes("i", [])

  Meta.allow_tag_with_uri_attributes("img", ["src"], @valid_schemes)

  Meta.allow_tag_with_these_attributes("img", [
    "width",
    "height",
    "title",
    "alt"
  ])

  Meta.allow_tag_with_these_attributes("li", [])
  Meta.allow_tag_with_these_attributes("ol", [])
  Meta.allow_tag_with_these_attributes("p", [])
  Meta.allow_tag_with_these_attributes("pre", [])
  Meta.allow_tag_with_these_attributes("span", [])
  Meta.allow_tag_with_these_attributes("strong", [])
  Meta.allow_tag_with_these_attributes("table", [])
  Meta.allow_tag_with_these_attributes("tbody", [])
  Meta.allow_tag_with_these_attributes("td", [])
  Meta.allow_tag_with_these_attributes("th", [])
  Meta.allow_tag_with_these_attributes("thead", [])
  Meta.allow_tag_with_these_attributes("tr", [])
  Meta.allow_tag_with_these_attributes("u", [])
  Meta.allow_tag_with_these_attributes("ul", [])

  # Custom handling for "style" tag
  def scrub({"style", attributes, [text]}) do
    {"style", style_scrub_attributes(attributes), [scrub_css(text)]}
  end

  defp style_scrub_attributes(attributes) do
    Enum.map(attributes, &style_scrub_attribute/1)
    |> Enum.reject(&is_nil/1)
  end

  defp style_scrub_attribute({"media", value}), do: {"media", value}
  defp style_scrub_attribute({"type", value}), do: {"type", value}
  defp style_scrub_attribute({"scoped", value}), do: {"scoped", value}
  defp style_scrub_attribute(_), do: nil

  defp scrub_css(text) do
    CSS.scrub(text)
  end

  @before_compile HtmlSanitizeEx.ScrubberCompiler
end
