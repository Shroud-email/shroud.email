defmodule Shroud.Email.Enricher do
  @moduledoc """
  Adds a "Forwarded by Shroud.email" header to an email.
  """

  alias Shroud.Util
  alias Shroud.Email.{ParsedEmail, ReplyAddress}

  alias ShroudWeb.Router.Helpers, as: Routes

  @spec process(ParsedEmail.t()) :: ParsedEmail.t()
  def process(%ParsedEmail{} = email) do
    email
    |> process_text()
    |> process_html()
  end

  defp process_text(%ParsedEmail{swoosh_email: %{text_body: nil}} = email),
    do: email

  defp process_text(%ParsedEmail{swoosh_email: swoosh_email} = email) do
    [{}]

    text_body = """
    This email was forwarded from #{recipient_alias(email)} by Shroud.email.

    #{swoosh_email.text_body}
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
        header = shroud_header(email)

        parsed_html
        |> Floki.traverse_and_update(fn
          {"body", attrs, children} ->
            {"body", attrs, [header | children]}

          other ->
            other
        end)
        |> Floki.raw_html()
    end
  end

  # If we can't process the HTML properly, just plonk this notice in
  # before the top <html> element. Ugly, but a decent fallback.
  defp html_fallback(html_body, email) do
    Appsignal.increment_counter("emails.html_fallback", 1)
    header = email |> shroud_header() |> Floki.raw_html()

    """
    #{header}

    #{html_body}
    """
  end

  defp shroud_header(%ParsedEmail{} = email) do
    {_sender_name, sender_address} = email.swoosh_email.from
    {sender_address, _email_alias} = ReplyAddress.from_reply_address(sender_address)

    trackers = email.removed_trackers

    report_data =
      %{
        sender: sender_address,
        email_alias: recipient_alias(email),
        trackers: trackers
      }
      |> Util.uri_encode_map!()

    report_uri = Routes.page_url(ShroudWeb.Endpoint, :email_report, report_data)

    trackers_word = if length(trackers) == 1, do: "tracker", else: "trackers"

    header_text =
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
           "background: #ffffff; background-color: #ffffff; margin:0px auto; padding: 5px; border-bottom: 3px solid #d271d2;"}
        ],
        [
          {"p",
           [
             {"style",
              "font-family: sans-serif; font-size: 13px; text-align: center; color: #444444; margin: 5px auto;"}
           ],
           [
             {"strong", [{"style", "color: #444444;"}], "Shroud.email "},
             header_text
           ]}
        ]
      }
    }
  end

  defp recipient_alias(email) do
    # TODO: we need to get this data from SmtpServer, otherwise
    # there's an edge case when there are multiple recipients
    {_name, recipient_address} =
      email.swoosh_email.to
      |> hd()

    recipient_address
  end
end
