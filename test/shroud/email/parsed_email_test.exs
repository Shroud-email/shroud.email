defmodule Shroud.Email.ParsedEmailTest do
  use Shroud.DataCase, async: true

  import Shroud.EmailFixtures
  alias Shroud.Email.ParsedEmail
  alias Shroud.Util

  @html_content """
    <html>
      <body>
        <h1>This is HTML content</h1>
        <p>Lorem ipsum</p>
      </body>
    </html>
  """
  @text_content "Text-only body"

  describe "process/1" do
    test "parses a text-only email" do
      email =
        text_email("sender@example.com", ["recipient@shroud.email"], "Subject", @text_content)
        |> :mimemail.decode()

      parsed = ParsedEmail.parse(email)

      assert parsed.removed_trackers == []
      assert parsed.swoosh_email.subject == "Subject"
      assert Util.crlf_to_lf(parsed.swoosh_email.text_body) == @text_content
      assert parsed.swoosh_email.from == {"sender@example.com", "sender@example.com"}
      assert parsed.swoosh_email.to == [{"recipient@shroud.email", "recipient@shroud.email"}]
      assert is_nil(parsed.swoosh_email.html_body)
      assert is_nil(parsed.parsed_html)
    end

    test "parses a HTML-only email" do
      email =
        html_email("sender@example.com", ["recipient@shroud.email"], "Subject", @html_content)
        |> :mimemail.decode()

      parsed = ParsedEmail.parse(email)

      assert parsed.removed_trackers == []
      assert parsed.swoosh_email.subject == "Subject"
      assert Util.crlf_to_lf(parsed.swoosh_email.html_body) == Util.crlf_to_lf(@html_content)
      assert parsed.swoosh_email.from == {"sender@example.com", "sender@example.com"}
      assert parsed.swoosh_email.to == [{"recipient@shroud.email", "recipient@shroud.email"}]
      assert is_nil(parsed.swoosh_email.text_body)
      assert not is_nil(parsed.parsed_html)
    end

    test "parses a multipart email" do
      email =
        multipart_email(
          "sender@example.com",
          ["recipient@shroud.email"],
          "Subject",
          @text_content,
          @html_content
        )
        |> :mimemail.decode()

      parsed = ParsedEmail.parse(email)

      assert parsed.removed_trackers == []
      assert parsed.swoosh_email.subject == "Subject"
      assert Util.crlf_to_lf(parsed.swoosh_email.html_body) == Util.crlf_to_lf(@html_content)
      assert parsed.swoosh_email.from == {"sender@example.com", "sender@example.com"}
      assert parsed.swoosh_email.to == [{"recipient@shroud.email", "recipient@shroud.email"}]
      assert Util.crlf_to_lf(parsed.swoosh_email.text_body) == @text_content
      assert not is_nil(parsed.parsed_html)
    end

    test "handles unicode email bodies (quoted-printable)" do
      email = File.read!("test/support/data/unicode_body.email") |> :mimemail.decode()

      %{swoosh_email: email} = ParsedEmail.parse(email)

      assert email.html_body =~ "①"
      assert email.html_body =~ "㏨"
      assert email.html_body =~ "λ"
    end

    test "handles unicode headers (encoded-word)" do
      email = File.read!("test/support/data/unicode_header.email") |> :mimemail.decode()

      %{swoosh_email: email} = ParsedEmail.parse(email)

      {sender, _sender_email} = email.from
      assert sender == "Pärla Example"
      assert email.subject == "Unicode PÄRLA test"
    end

    test "handles an application/octet attachment" do
      email = File.read!("test/support/data/single_attachment.email") |> :mimemail.decode()

      %{swoosh_email: email} = ParsedEmail.parse(email)

      assert length(email.attachments) == 1
      assert hd(email.attachments).filename == "motherofalldemos.jpg"
      assert hd(email.attachments).content_type == "image/jpeg"
    end

    test "handles an image/jpeg attachment" do
      email = File.read!("test/support/data/attachment_image.email") |> :mimemail.decode()

      %{swoosh_email: email} = ParsedEmail.parse(email)

      assert length(email.attachments) == 1
      assert hd(email.attachments).filename == "motherofalldemos.jpg"
      assert hd(email.attachments).content_type == "image/jpeg"
    end

    test "handles multiple attachments" do
      email = File.read!("test/support/data/multiple_attachments.email") |> :mimemail.decode()

      %{swoosh_email: email} = ParsedEmail.parse(email)

      assert length(email.attachments) == 2

      assert Enum.map(email.attachments, &Map.get(&1, :filename)) == [
               "internet.jpg",
               "motherofalldemos.jpg"
             ]

      assert Enum.map(email.attachments, &Map.get(&1, :content_type)) == [
               "image/jpeg",
               "image/jpeg"
             ]
    end

    test "handles an inline attachment" do
      email = File.read!("test/support/data/inline_attachment.email") |> :mimemail.decode()

      %{swoosh_email: email} = ParsedEmail.parse(email)

      assert length(email.attachments) == 1
      attachment = hd(email.attachments)
      assert attachment.filename == "motherofalldemos.jpg"
      assert attachment.content_type == "image/jpeg"
      assert attachment.cid == "708f1df0@example.com"
    end
  end
end
