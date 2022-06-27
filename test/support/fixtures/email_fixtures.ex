defmodule Shroud.EmailFixtures do
  @moduledoc """
  This module defines test helpers for creating
  the DATA portion of received emails.
  """

  alias Shroud.Util

  @spec multipart_email(String.t(), [String.t()], String.t(), String.t(), String.t()) ::
          String.t()
  def multipart_email(sender, recipients, subject, text_content, html_content) do
    boundary = "gc0p4Jq0M2Yt08jU534c0p"

    """
    Content-Type: multipart/alternative; boundary="#{boundary}"

    --#{boundary}
    Content-Type: text/plain
    Content-Transfer-Encoding: quoted-printable
    Content-Disposition: inline

    #{text_content}

    --#{boundary}
    Content-Type: text/HTML
    Content-Transfer-Encoding: quoted-printable
    Content-Disposition: inline

    #{html_content}

    --#{boundary}--
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> Util.lf_to_crlf()
  end

  @spec html_email(String.t(), [String.t()], String.t(), String.t()) :: String.t()
  def html_email(sender, recipients, subject, content) do
    """
    Content-Type: text/HTML

    #{content}
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> Util.lf_to_crlf()
  end

  @spec text_email(String.t(), [String.t()], String.t(), String.t()) :: String.t()
  def text_email(sender, recipients, subject, content, extra_header \\ nil) do
    """
    Content-Type: text/plain

    #{content}
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> add_header(extra_header)
    |> Util.lf_to_crlf()
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
    recipients = Enum.map_join(recipients, ", ", &format_address/1)

    """
    To: #{recipients}
    """ <> data
  end

  defp add_header(data, nil), do: data

  defp add_header(data, header) do
    header <> "\n" <> data
  end

  defp format_address({name, address}), do: "\"#{name}\" <#{address}>"
  defp format_address(address), do: address
end
