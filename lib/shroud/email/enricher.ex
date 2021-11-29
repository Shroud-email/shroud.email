defmodule Shroud.Email.Enricher do
  @moduledoc """
  Adds a "Forwarded by Shroud.email" header to an email.
  """

  alias Shroud.Email.ParsedEmail

  @spec process(ParsedEmail.t()) :: ParsedEmail.t()
  def process(%ParsedEmail{} = email) do
    [{_recipient_name, recipient_alias}] = email.swoosh_email.to

    email
    |> process_text(recipient_alias)
    |> process_html(recipient_alias)
  end

  defp process_text(%ParsedEmail{swoosh_email: %{text_body: nil}} = email, _recipient_alias),
    do: email

  defp process_text(%ParsedEmail{swoosh_email: swoosh_email} = email, recipient_alias) do
    text_body = """
    This email was forwarded from #{recipient_alias} by Shroud.email.

    #{swoosh_email.text_body}
    """

    swoosh_email = %Swoosh.Email{swoosh_email | text_body: text_body}
    %{email | swoosh_email: swoosh_email}
  end

  defp process_html(%ParsedEmail{swoosh_email: %{html_body: nil}} = email, _recipient_alias),
    do: email

  defp process_html(
         %ParsedEmail{swoosh_email: swoosh_email, parsed_html: parsed_html} = email,
         recipient_alias
       ) do
    html_body =
      if is_nil(parsed_html) do
        html_fallback(swoosh_email.html_body, recipient_alias)
      else
        enrich_parsed_html(parsed_html, recipient_alias)
      end

    swoosh_email = %Swoosh.Email{swoosh_email | html_body: html_body}
    %{email | swoosh_email: swoosh_email}
  end

  defp enrich_parsed_html(parsed_html, recipient_alias) do
    case Floki.find(parsed_html, "body") do
      [] ->
        # No <body> element for some reason; use fallback
        parsed_html |> Floki.raw_html() |> html_fallback(recipient_alias)

      _body ->
        header = shroud_header(recipient_alias)

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
  defp html_fallback(html_body, recipient_alias) do
    Appsignal.increment_counter("emails.html_fallback", 1)
    header = recipient_alias |> shroud_header() |> Floki.raw_html()

    """
    #{header}

    #{html_body}
    """
  end

  defp shroud_header(recipient_alias) do
    {
      "div",
      [
        {"style",
         "background: #3d4451; background-color: #3d4451; margin:0px auto; padding: 5px; border-bottom: 2px solid #793ef9;"}
      ],
      [
        {"p",
         [
           {"style",
            "font-family: sans-serif; font-size: 13px; text-align: center; color: #ebecf0;"}
         ],
         [
           "This message was forwarded from ",
           {"strong", [], [recipient_alias]},
           " by ",
           {"a",
            [
              {"href", "https://shroud.email"},
              {"target", "_blank"},
              {"style", "text-decoration: none; color: #ebecf0;"}
            ],
            [
              {"strong", [{"style", "color: #ebecf0;"}], ["Shroud.email"]}
            ]},
           "."
         ]}
      ]
    }
  end
end
