defmodule Shroud.Email.TrackerRemover do
  @moduledoc """
  This module removes trackers from the HTML part of a Swoosh email.
  This works in a few ways:
  - Compare all image URLs to a list of known tracker regexes
  - Remove any 1x1 (or 2x2) images
  - Replace all image URLs with ones proxied through this app
  - TODO: look at other external resources like fonts
  - TODO: look at images with URL params, even if they're not on the blocklist
  - TODO: handle tracking links (automatically click them)
  """

  # TODO: look into also handling text emails (i.e. just tracking links)
  # once we enable tracking-link-processing

  alias Shroud.Email
  alias Shroud.Email.{ImageSources, ParsedEmail, Tracker}
  use ShroudWeb, :verified_routes

  @spec process(ParsedEmail.t()) :: ParsedEmail.t()
  def process(%ParsedEmail{parsed_html: nil} = email), do: email

  def process(%ParsedEmail{parsed_html: parsed_html} = email) do
    trackers = Email.list_trackers()

    # Each removed image accumulates a `%{name, domain}` entry: `name` is the
    # friendly tracker name (nil for unknown pixels) shown in the user's report,
    # and `domain` is the real host extracted from the image URL, which is what
    # we persist for analytics.
    {processed_html, removed_trackers} =
      ImageSources.map(parsed_html, &process_source(trackers, &1, &2, &3), [])

    # Entries are accumulated by prepending, so reverse to restore the order in
    # which they appeared in the email, then deduplicate so an identical tracker
    # isn't recorded multiple times.
    removed_trackers =
      removed_trackers
      |> Enum.reverse()
      |> Enum.uniq()

    swoosh_email = struct(email.swoosh_email, html_body: Floki.raw_html(processed_html))

    struct(email,
      parsed_html: processed_html,
      removed_trackers: removed_trackers,
      swoosh_email: swoosh_email
    )
  end

  defp process_source(trackers, source, image_attrs, acc) do
    tracker = Enum.find(trackers, &Tracker.match?(&1, source))

    if tracker || tiny_image?(image_attrs) do
      entry = %{name: if(tracker, do: tracker.name), domain: URI.parse(source).host}
      {nil, [entry | acc]}
    else
      {url(~p"/proxy?url=#{source}"), acc}
    end
  end

  defp tiny_image?(nil), do: false

  defp tiny_image?(attrs) do
    {"width", width} = Enum.find(attrs, {"width", "999"}, &match?({"width", _width}, &1))
    {"height", height} = Enum.find(attrs, {"height", "999"}, &match?({"height", _height}, &1))

    with {width, _rem} <- parse_size(width),
         {height, _rem} <- parse_size(height) do
      width < 3 and height < 3
    else
      :error -> false
    end
  end

  defp parse_size(size) do
    size
    |> String.trim()
    |> String.replace_suffix("px", "")
    |> String.replace_suffix("rem", "")
    |> String.replace_suffix("em", "")
    |> Integer.parse()
  end
end
