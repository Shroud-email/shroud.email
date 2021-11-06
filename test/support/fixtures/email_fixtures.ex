defmodule Shroud.EmailFixtures do
  @moduledoc """
  This module defines test helpers for creating
  the DATA portion of received emails.
  """

  def multipart_email(sender, recipients, subject, text_content, html_content) do
    boundary = "gc0p4Jq0M2Yt08jU534c0p"

    """
    Content-Type: multipart/alternative; boundary="#{boundary}"

    --#{boundary}
    Content-Type: text/plain; charset="utf-8"
    Content-Transfer-Encoding: quoted-printable
    Content-Disposition: inline

    #{text_content}

    --#{boundary}
    Content-Type: text/HTML; charset="utf-8"
    Content-Transfer-Encoding: quoted-printable
    Content-Disposition: inline

    #{html_content}

    --#{boundary}--
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> convert_newlines()
  end

  def html_email(sender, recipients, subject, content) do
    """
    Content-Type: text/HTML; charset="utf-8"

    #{content}
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> convert_newlines()
  end

  def text_email(sender, recipients, subject, content) do
    """
    Content-Type: text/plain; charset="utf-8"

    #{content}
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> convert_newlines()
  end

  defp add_subject(data, subject) do
    """
    Subject: #{subject}
    """ <> data
  end

  defp add_sender(data, sender) do
    """
    From: #{format_address(sender)}
    """ <> data
  end

  defp add_recipients(data, recipients) do
    recipients =
      recipients
      |> Enum.map(&format_address/1)
      |> Enum.join(", ")

    """
    To: #{recipients}
    """ <> data
  end

  defp format_address({name, address}), do: "\"#{name}\" <#{address}>"
  defp format_address(address), do: address

  # Emails require CRLF newlines
  defp convert_newlines(data) do
    String.replace(data, "\n", "\r\n")
  end
end
