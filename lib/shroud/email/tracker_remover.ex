defmodule Shroud.Email.TrackerRemover do
  @moduledoc """
  This module removes trackers from the HTML part of a Swoosh email.
  This works in a few ways:
  - Compare all image URLs to a list of known tracker regexes
  - Remove any 1x1 (or 2x2) images
  - TODO: look at other external resources like fonts
  - TODO: look at images with URL params, even if they're not on the blocklist
  - TODO: handle tracking links (automatically click them)
  - TODO: open everything as soon as the email is received (like Mail Privacy Protection)
  - TODO: maybe proxy images/assets
  """

  # TODO: look into also handling text emails (i.e. just tracking links)
  # once we enable tracking-link-processing

  alias Shroud.Email
  alias Shroud.Email.{ParsedEmail, Tracker}

  @spec process(ParsedEmail.t()) :: ParsedEmail.t()
  def process(%ParsedEmail{parsed_html: nil} = email), do: email

  def process(%ParsedEmail{parsed_html: parsed_html} = email) do
    trackers = Email.list_trackers()

    {processed_html, removed_trackers} =
      Floki.traverse_and_update(parsed_html, [], fn
        {"img", attrs, children}, acc -> process_image(trackers, attrs, children, acc)
        other, acc -> {other, acc}
      end)

    swoosh_email = struct(email.swoosh_email, html_body: Floki.raw_html(processed_html))

    struct(email,
      parsed_html: processed_html,
      removed_trackers: removed_trackers,
      swoosh_email: swoosh_email
    )
  end

  defp process_image(trackers, attrs, children, acc) do
    # Look for known trackers
    removed_tracker =
      attrs
      |> Enum.map(&check_attribute(trackers, &1))
      |> Enum.find(%{name: nil}, &(not is_nil(&1)))
      |> Map.get(:name)

    # Look for tracking pixels from unknown sources
    removed_tracker =
      if is_nil(removed_tracker) do
        find_unknown_tracker(attrs)
      else
        removed_tracker
      end

    if is_nil(removed_tracker) do
      {{"img", attrs, children}, acc}
    else
      # Returning nil removes this img element from the HTML
      {nil, [removed_tracker | acc]}
    end
  end

  defp check_attribute(trackers, {"src", source}) do
    Enum.find(trackers, fn tracker -> Tracker.match?(tracker, source) end)
  end

  defp check_attribute(_trackers, _attr), do: nil

  defp find_unknown_tracker(attrs) do
    {"width", width} = Enum.find(attrs, {"width", "999"}, &match?({"width", _width}, &1))
    {"height", height} = Enum.find(attrs, {"height", "999"}, &match?({"height", _height}, &1))
    {"src", source} = Enum.find(attrs, {"src", nil}, &match?({"src", _src}, &1))

    {width, _rem} = Integer.parse(width)
    {height, _rem} = Integer.parse(height)

    if width < 3 and height < 3 and not is_nil(source) do
      source
      |> URI.parse()
      |> Map.get(:host)
    end
  end
end
