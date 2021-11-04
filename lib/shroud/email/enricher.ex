defmodule Shroud.Email.Enricher do
  @moduledoc """
  This module handles the processing of the actual body of emails,
  whether HTML or plaintext.
  """

  @spec process(Swoosh.Email.t()) :: Swoosh.Email.t()
  def process(%Swoosh.Email{} = email) do
    [{_recipient_name, recipient_alias}] = email.to

    email
    |> process_text(recipient_alias)
    |> process_html(recipient_alias)
  end

  defp process_text(%{text_body: nil} = email, _recipient_alias), do: email

  defp process_text(email, recipient_alias) do
    text_body = """
    This email was forwarded from #{recipient_alias} by Shroud.email.

    #{email.text_body}
    """

    %{email | text_body: text_body}
  end

  defp process_html(%{html_body: nil} = email, _recipient_alias), do: email

  defp process_html(email, recipient_alias) do
    html_body =
      case Floki.parse_document(email.html_body) do
        {:ok, parsed} ->
          enrich_parsed_html(parsed, recipient_alias)

        {:error, _error} ->
          html_fallback(email.html_body, recipient_alias)
      end

    %{email | html_body: html_body}
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
            "font-family: sans-serif; font-size: 13px; text-align: center; color: #ebecf0"}
         ],
         [
           "This message was forwarded from ",
           {"strong", [], [recipient_alias]},
           " by ",
           {"a",
            [
              {"href", "https://shroud.email"},
              {"target", "_blank"},
              {"style", "text-decoration: none; color: #ebecf0"}
            ], ["Shroud.email"]},
           "."
         ]}
      ]
    }
  end
end
