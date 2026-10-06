defmodule Shroud.Email.InboxEmailTest do
  use ExUnit.Case, async: true
  alias Shroud.Email.InboxEmail
  import Shroud.InboxesFixtures

  test "8bit and quoted-printable attachments preserve bytes and line endings" do
    for {encoding, encoded, expected} <- [
          {"8bit", <<"café\r\n", 0, 255, "\r\n">>, <<"café\r\n", 0, 255, "\r\n">>},
          {"quoted-printable", "caf=C3=A9=0D=0A=00=FF", <<"café\r\n", 0, 255>>}
        ] do
      raw =
        email_with_attachment()
        |> String.replace("application/pdf", "text/plain; charset=iso-8859-1")
        |> String.replace(
          "Content-Transfer-Encoding: base64",
          "Content-Transfer-Encoding: #{encoding}"
        )
        |> String.replace("JVBERi0xLjQKAAEC", encoded)

      email = InboxEmail.parse(raw, "sender@example.com", "recipient@example.com")
      assert email.text_body =~ "09:45"
      assert [attachment] = email.attachments
      assert attachment.data == expected
    end
  end

  test "nested multipart with a regex-sensitive boundary preserves attachments" do
    raw =
      email_with_attachment()
      |> String.replace("inbox-test", "inner.+[]")

    raw =
      "Content-Type: multipart/mixed; boundary=outer\r\n\r\nPreamble\r\n--outer\r\n" <>
        raw <> "\r\n--outer--\r\nEpilogue"

    email = InboxEmail.parse(raw, "sender@example.com", "recipient@example.com")
    assert email.text_body =~ "09:45"
    assert [attachment] = email.attachments
    assert attachment.data == <<"%PDF-1.4\n", 0, 1, 2>>
  end

  test "single-part attachment is downloadable and does not become body text" do
    raw =
      "Subject: A file\r\nContent-Type: text/plain\r\nContent-Disposition: attachment; filename=notes.txt\r\n\r\nPrivate notes\r\n"

    email = InboxEmail.parse(raw, "sender@example.com", "recipient@example.com")
    assert email.subject == "A file"
    assert email.text_body in [nil, ""]
    assert [attachment] = email.attachments
    assert attachment.data == "Private notes\r\n"
  end

  test "inline text without a filename is message content, not an attachment" do
    raw = "Content-Type: text/plain\r\nContent-Disposition: inline\r\n\r\nThe message body"
    email = InboxEmail.parse(raw, "sender@example.com", "recipient@example.com")
    assert email.text_body == "The message body"
    assert email.attachments == []
  end
end
