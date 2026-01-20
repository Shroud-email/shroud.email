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

      parsed = ParsedEmail.parse(email, "sender@example.com", "recipient@shroud.email")

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

      parsed = ParsedEmail.parse(email, "sender@example.com", "recipient@shroud.email")

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

      parsed = ParsedEmail.parse(email, "sender@example.com", "recipient@shroud.email")

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

      %{swoosh_email: email} =
        ParsedEmail.parse(email, "sender@example.com", "alias@email.shroud.test")

      assert email.html_body =~ "①"
      assert email.html_body =~ "㏨"
      assert email.html_body =~ "λ"
    end

    test "handles unicode headers (encoded-word)" do
      email = File.read!("test/support/data/unicode_header.email") |> :mimemail.decode()

      %{swoosh_email: email} =
        ParsedEmail.parse(email, "sender@example.com", "alias@email.shroud.test")

      {sender, _sender_email} = email.from
      assert sender == "Pärla Example"
      assert email.subject == "Unicode PÄRLA test"
    end

    test "handles an application/octet attachment" do
      email = File.read!("test/support/data/single_attachment.email") |> :mimemail.decode()

      %{swoosh_email: email} =
        ParsedEmail.parse(email, "sender@example.com", "alias@email.shroud.test")

      assert length(email.attachments) == 1
      assert hd(email.attachments).filename == "motherofalldemos.jpg"
      assert hd(email.attachments).content_type == "image/jpeg"
    end

    test "handles an image/jpeg attachment" do
      email = File.read!("test/support/data/attachment_image.email") |> :mimemail.decode()

      %{swoosh_email: email} =
        ParsedEmail.parse(email, "sender@example.com", "alias@email.shroud.test")

      assert length(email.attachments) == 1
      assert hd(email.attachments).filename == "motherofalldemos.jpg"
      assert hd(email.attachments).content_type == "image/jpeg"
    end

    test "handles multiple attachments" do
      email = File.read!("test/support/data/multiple_attachments.email") |> :mimemail.decode()

      %{swoosh_email: email} =
        ParsedEmail.parse(email, "sender@example.com", "alias@email.shroud.test")

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

      %{swoosh_email: email} =
        ParsedEmail.parse(email, "sender@example.com", "alias@email.shroud.test")

      assert length(email.attachments) == 1
      attachment = hd(email.attachments)
      assert attachment.filename == "motherofalldemos.jpg"
      assert attachment.content_type == "image/jpeg"
      assert attachment.cid == "708f1df0@example.com"
    end

    test "sanitizes email addresses with spaces in the local part" do
      # This reproduces an error where malformed email addresses with spaces
      # cause gen_smtp/mimemail to fail with:
      # (ArgumentError) errors were found at the given arguments:
      #   * 1st argument: not an atom
      #   :erlang.atom_to_list(~c"bar_at_example")
      email_raw =
        text_email(
          {"foo bar", "foo bar@example.com"},
          ["info@example.com"],
          "Test email with malformed address",
          "Test body",
          "Reply-To: \"foo bar\" <foo bar@example.com>"
        )

      mimemail_email = :mimemail.decode(email_raw)

      %{swoosh_email: email} =
        ParsedEmail.parse(mimemail_email, "sender@example.com", "alias@email.shroud.test")

      # Verify the address was sanitized (spaces removed from local part)
      {from_name, from_address} = email.from
      assert from_name == "foo bar"
      assert from_address == "foobar@example.com"

      # Verify reply_to was also sanitized
      {_reply_to_name, reply_to_address} = email.reply_to
      assert reply_to_address == "foobar@example.com"
    end

    test "sanitizes email addresses with invalid bracket domains like [domain]" do
      # This reproduces an error where bracket domains that are not valid IP addresses
      # cause gen_smtp/mimemail to crash with:
      # (MatchError) no match of right hand side value:
      #   {:error, {1, :smtp_rfc5322_parse, [~c"syntax error before: ", [~c"\"[invalid]\""]]}}
      # Brackets in domains are only valid for IP address literals like [192.168.1.1]
      email_raw =
        text_email(
          {"John Doe", "john@[invalid]"},
          ["info@example.com"],
          "Test email with bracket domain",
          "Test body",
          "Reply-To: \"Jane Doe\" <jane@[invalid]>"
        )

      mimemail_email = :mimemail.decode(email_raw)

      %{swoosh_email: email} =
        ParsedEmail.parse(mimemail_email, "sender@example.com", "alias@email.shroud.test")

      # Verify the address was sanitized (brackets removed from invalid domain)
      {from_name, from_address} = email.from
      assert from_name == "John Doe"
      assert from_address == "john@invalid"

      # Verify reply_to was also sanitized
      {_reply_to_name, reply_to_address} = email.reply_to
      assert reply_to_address == "jane@invalid"
    end

    test "preserves valid IP address bracket notation in domains" do
      # Valid IP address literals in brackets should be preserved
      email_raw =
        text_email(
          {"Test Sender", "user@[192.168.1.1]"},
          ["info@example.com"],
          "Test email with IP literal domain",
          "Test body"
        )

      mimemail_email = :mimemail.decode(email_raw)

      %{swoosh_email: email} =
        ParsedEmail.parse(mimemail_email, "sender@example.com", "alias@email.shroud.test")

      # Valid IP address literals should be preserved
      {_from_name, from_address} = email.from
      assert from_address == "user@[192.168.1.1]"
    end
  end
end
