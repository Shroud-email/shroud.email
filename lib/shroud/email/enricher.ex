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
    text_body =
      Phoenix.View.render_to_string(Shroud.EmailView, "email.txt",
        body: email.text_body,
        recipient_alias: recipient_alias
      )

    %{email | text_body: text_body}
  end

  defp process_html(%{html_body: nil} = email, _recipient_alias), do: email

  defp process_html(email, recipient_alias) do
    html_body =
      Phoenix.View.render_to_string(Shroud.EmailView, "email.html", %{
        body: email.html_body,
        recipient_alias: recipient_alias
      })

    %{email | html_body: html_body}
  end
end
