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
  alias Shroud.Email.{Enricher, ImageSources, ParsedEmail, Tracker}
  use ShroudWeb, :verified_routes
  require Logger

  @privacy_budget 2_000

  @spec process(ParsedEmail.t(), boolean()) :: ParsedEmail.t()
  def process(email, branding \\ false)
  def process(%ParsedEmail{privacy_processing_failed: true} = email, _branding), do: email

  def process(email, branding) do
    task =
      Task.Supervisor.async_nolink(Shroud.Email.PrivacyTasks, fn ->
        {:ok, timer} = :timer.exit_after(@privacy_budget, self(), :kill)

        try do
          trackers = if email.parsed_html, do: Email.list_trackers(), else: []
          processed = process_html(email, trackers)
          if branding, do: Enricher.process(processed), else: processed
        rescue
          _ -> fail_open(email)
        catch
          _, _ -> fail_open(email)
        after
          :timer.cancel(timer)
        end
      end)

    case Task.yield(task, @privacy_budget) do
      {:ok, processed} ->
        processed

      _ ->
        Task.shutdown(task, :brutal_kill)
        fail_open(email)
    end
  rescue
    _ -> fail_open(email)
  catch
    _, _ -> fail_open(email)
  end

  defp process_html(%ParsedEmail{parsed_html: nil} = email, _trackers), do: email

  defp process_html(%ParsedEmail{parsed_html: parsed_html} = email, trackers) do
    # Each removed image accumulates a `%{name, domain}` entry: `name` is the
    # friendly tracker name (nil for unknown pixels) shown in the user's report,
    # and `domain` is the real host extracted from the image URL, which is what
    # we persist for analytics.
    {processed_html, {removed_trackers, image_urls}} =
      ImageSources.map(parsed_html, &process_source(trackers, &1, &2, &3), {[], []})

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
      image_urls: image_urls |> Enum.reverse() |> Enum.uniq(),
      swoosh_email: swoosh_email
    )
  end

  defp fail_open(email) do
    Logger.warning("Email privacy processing failed; forwarding the original content")
    %{email | privacy_processing_failed: true}
  end

  defp process_source(trackers, source, image_attrs, {removed, urls}) do
    tracker = Enum.find(trackers, &Tracker.match?(&1, source))

    if tracker || tiny_image?(image_attrs) do
      entry = %{name: if(tracker, do: tracker.name), domain: URI.parse(source).host}
      {nil, {[entry | removed], [source | urls]}}
    else
      {url(~p"/proxy?url=#{source}"), {removed, [source | urls]}}
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
