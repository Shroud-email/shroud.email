defmodule Shroud.Email.Enricher do
  @moduledoc """
  Adds a "Forwarded by Shroud.email" footer to an email.
  """

  alias Shroud.Util
  alias Shroud.Email.ParsedEmail
  use ShroudWeb, :verified_routes

  @spec process(ParsedEmail.t()) :: ParsedEmail.t()
  def process(%ParsedEmail{} = email) do
    email
    |> process_text()
    |> process_html()
  end

  defp process_text(%ParsedEmail{swoosh_email: %{text_body: nil}} = email),
    do: email

  defp process_text(%ParsedEmail{to: to_alias, swoosh_email: swoosh_email} = email) do
    [{}]

    text_body = """
    #{swoosh_email.text_body}

    This email was forwarded from #{to_alias} by Shroud.email.
    """

    swoosh_email = %Swoosh.Email{swoosh_email | text_body: text_body}
    %{email | swoosh_email: swoosh_email}
  end

  defp process_html(%ParsedEmail{swoosh_email: %{html_body: nil}} = email),
    do: email

  defp process_html(%ParsedEmail{swoosh_email: swoosh_email, parsed_html: parsed_html} = email) do
    html_body =
      if is_nil(parsed_html) do
        html_fallback(swoosh_email.html_body, email)
      else
        enrich_parsed_html(email)
      end

    swoosh_email = %Swoosh.Email{swoosh_email | html_body: html_body}
    %{email | swoosh_email: swoosh_email}
  end

  defp enrich_parsed_html(%ParsedEmail{parsed_html: parsed_html} = email) do
    case Floki.find(parsed_html, "body") do
      [] ->
        # No <body> element for some reason; use fallback
        parsed_html |> Floki.raw_html() |> html_fallback(email)

      _body ->
        footer = shroud_footer(email)

        parsed_html
        |> Floki.traverse_and_update(fn
          {"body", attrs, children} ->
            {"body", attrs, children ++ [footer]}

          other ->
            other
        end)
        |> Floki.raw_html()
    end
  end

  # If we can't process the HTML properly, just plonk this notice in
  # after the top <html> element. Ugly, but a decent fallback.
  defp html_fallback(html_body, email) do
    footer = email |> shroud_footer() |> Floki.raw_html()

    """
    #{html_body}

    #{footer}
    """
  end

  defp shroud_footer(%ParsedEmail{to: to_alias} = email) do
    {_sender_name, sender_address} = email.swoosh_email.from

    trackers = email.removed_trackers

    report_data =
      %{
        sender: sender_address,
        email_alias: to_alias,
        trackers: trackers
      }
      |> Util.uri_encode_map!()

    report_uri = url(~p"/email-report/#{report_data}")

    trackers_word = if length(trackers) == 1, do: "tracker", else: "trackers"

    footer_text =
      if Enum.empty?(trackers),
        do: "didn't find any trackers.",
        else: "removed #{length(trackers)} #{trackers_word}."

    {
      "a",
      [
        {"href", report_uri},
        {"target", "_blank"},
        {"rel", "noreferrer noopener"},
        {"style", "text-decoration: none !important; text-decoration: none;"}
      ],
      {
        "div",
        [
          {"style",
           "background: #ffffff; background-color: #ffffff; margin:0px auto; padding: 5px;"}
        ],
        [
          {"p",
           [
             {"style",
              "font-family: sans-serif; font-size: 13px; text-align: center; color: #444444; margin: 5px auto;"}
           ], "This email was forwarded by Shroud.email. We #{footer_text}"}
        ]
      }
    }
  end
end
