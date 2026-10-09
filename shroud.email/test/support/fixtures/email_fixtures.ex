defmodule Shroud.EmailFixtures do
  @moduledoc """
  This module defines test helpers for creating
  the DATA portion of received emails, and the SpamEmail
  schema.
  """

  alias Shroud.Repo
  alias Shroud.Util
  alias Shroud.Email.SpamEmail
  alias Swoosh.Adapters.SMTP.Helpers
  import Shroud.AccountsFixtures
  import Shroud.AliasesFixtures

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

  @spec html_email(String.t(), [String.t()], String.t(), String.t(), String.t()) :: String.t()
  def html_email(sender, recipients, subject, content, extra_header \\ nil) do
    """
    Content-Type: text/HTML

    #{content}
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> add_header(extra_header)
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

  def delivery_status_report(email, opts \\ []) do
    {_name, recipient} = hd(email.to)
    recipient = Keyword.get(opts, :recipient, recipient)
    action = Keyword.get(opts, :action, "failed")
    status = Keyword.get(opts, :status, "5.1.1")
    original = Helpers.body(email, []) |> String.replace("\r\n", "\n")

    {original_type, original} =
      case Keyword.get(opts, :original_format, :headers) do
        :headers -> {"text/rfc822-headers", original |> String.split("\n\n", parts: 2) |> hd()}
        :full -> {"message/rfc822", original}
      end

    """
    Content-Type: multipart/report; report-type=delivery-status; boundary="bounce-fixture"
    Subject: Delivery status

    --bounce-fixture
    Content-Type: text/plain

    Untrusted diagnostic content: https://malicious.example/private
    --bounce-fixture
    Content-Type: message/delivery-status

    Reporting-MTA: dns; mx.example.net

    Final-Recipient: rfc822; unrelated@example.net
    Action: failed
    Status: 5.2.2

    Final-Recipient: rfc822; #{recipient}
    Action: #{action}
    Status: #{status}
    Diagnostic-Code: smtp; private diagnostic recipient@example.net

    --bounce-fixture
    Content-Type: #{original_type}

    #{original}
    --bounce-fixture--
    """
    |> Util.lf_to_crlf()
  end

  @doc """
  Creates an email with invalid quoted-printable encoding in the body.
  This simulates malformed emails that contain sequences like =p, =m, =g
  instead of valid =XX hex sequences, which cause :mimemail.decode to throw :badchar.
  """
  @spec invalid_quoted_printable_email(String.t(), [String.t()], String.t(), String.t()) ::
          String.t()
  def invalid_quoted_printable_email(sender, recipients, subject, extra_header \\ nil) do
    # Invalid quoted-printable: =p is invalid (should be =XX where XX are hex digits)
    invalid_body = "Test content with invalid =p quoted-printable =m encoding =g here"

    """
    Content-Type: text/plain; charset=UTF-8
    Content-Transfer-Encoding: quoted-printable

    #{invalid_body}
    """
    |> add_subject(subject)
    |> add_sender(sender)
    |> add_recipients(recipients)
    |> add_header(extra_header)
    |> Util.lf_to_crlf()
  end

  def spam_email_fixture(attrs \\ %{}, user \\ nil, email_alias \\ nil) do
    user = if user, do: user, else: user_fixture()
    email_alias = if email_alias, do: email_alias, else: alias_fixture(%{user_id: user.id})

    attrs =
      Enum.into(attrs, %{
        from: "spammer@example.com",
        subject: "Spamspamspam",
        text_body: "Spam",
        html_body: "<html>spam</html>",
        spamassassin_header: "Yes, score=5.0 required=5.0 tests=TEST autolearn=ham version=3.4.1",
        user_id: user.id,
        email_alias_id: email_alias.id
      })

    %SpamEmail{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
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
