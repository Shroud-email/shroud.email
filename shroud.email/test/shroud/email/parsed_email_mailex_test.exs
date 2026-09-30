defmodule Shroud.Email.ParsedEmailMailexTest do
  use ExUnit.Case, async: true

  alias Shroud.Email.ParsedEmail

  @simple_email File.read!("test/support/data/real/simple.eml")
  @complex_email File.read!("test/support/data/real/integrityinstitute.eml")

  describe "parse/3 with Mailex.Message" do
    test "parses multipart/alternative email with text and html" do
      {:ok, mailex_msg} = Mailex.parse(@simple_email)

      result = ParsedEmail.parse(mailex_msg, "sender@example.com", "alias@example.com")

      assert %ParsedEmail{} = result
      assert result.from == "sender@example.com"
      assert result.to == "alias@example.com"

      swoosh = result.swoosh_email
      assert swoosh.subject == "heehee"
      assert {_, "sender@example.com"} = swoosh.from
      assert swoosh.text_body != nil
      assert swoosh.html_body != nil
      assert result.parsed_html != nil
    end

    test "extracts from header with name" do
      {:ok, mailex_msg} = Mailex.parse(@simple_email)

      result = ParsedEmail.parse(mailex_msg, "sender@example.com", "alias@example.com")

      {name, address} = result.swoosh_email.from
      assert name == "Shroud.email"
      assert address == "sender@example.com"
    end

    test "extracts to header" do
      {:ok, mailex_msg} = Mailex.parse(@simple_email)

      result = ParsedEmail.parse(mailex_msg, "sender@example.com", "alias@example.com")

      [{name, address}] = result.swoosh_email.to
      assert name == "Whatever"
      assert address == "alias@example.com"
    end

    test "handles complex email with attachments" do
      {:ok, mailex_msg} = Mailex.parse(@complex_email)

      result = ParsedEmail.parse(mailex_msg, "sender@test.com", "recipient@test.com")

      assert %ParsedEmail{} = result
      assert result.swoosh_email.subject != nil
    end

    test "produces equivalent output to mimemail parsing" do
      {:ok, mailex_msg} = Mailex.parse(@simple_email)
      mimemail_tuple = :mimemail.decode(@simple_email)

      mailex_result = ParsedEmail.parse(mailex_msg, "sender@example.com", "alias@example.com")

      mimemail_result =
        ParsedEmail.parse(mimemail_tuple, "sender@example.com", "alias@example.com")

      assert mailex_result.swoosh_email.subject == mimemail_result.swoosh_email.subject

      normalize = fn str -> str |> String.replace("\r\n", "\n") |> String.trim() end

      assert normalize.(mailex_result.swoosh_email.text_body) ==
               normalize.(mimemail_result.swoosh_email.text_body)

      assert normalize.(mailex_result.swoosh_email.html_body) ==
               normalize.(mimemail_result.swoosh_email.html_body)
    end

    test "handles empty Reply-To header without crashing" do
      email_with_empty_reply_to = """
      From: "Sender" <sender@example.com>
      To: recipient@example.com
      Subject: Test email
      Reply-To: 
      Date: Tue, 28 Oct 2025 13:11:03 +0000
      Content-Type: text/plain; charset=UTF-8

      Hello, world!
      """

      {:ok, mailex_msg} = Mailex.parse(email_with_empty_reply_to)

      result = ParsedEmail.parse(mailex_msg, "sender@example.com", "recipient@example.com")

      assert %ParsedEmail{} = result
      assert result.swoosh_email.subject == "Test email"
      assert result.swoosh_email.reply_to == nil
    end

    test "decodes a windows-1252 subject so it survives SMTP re-encoding" do
      # Regression: a windows-1252 Subject used to leave raw, non-UTF-8 bytes in
      # the forwarded email, crashing :mimemail.rfc2047_utf8_encode/7 (a
      # FunctionClauseError) when gen_smtp re-encoded the headers for delivery.
      raw =
        "Subject: =?windows-1252?Q?=93Hi=94_=96_there?=\r\n" <>
          "From: sender@example.com\r\n" <>
          "To: alias@example.com\r\n" <>
          "Content-Type: text/plain\r\n\r\nhi\r\n"

      {:ok, mailex_msg} = Mailex.parse(raw)
      result = ParsedEmail.parse(mailex_msg, "sender@example.com", "alias@example.com")

      subject = result.swoosh_email.subject
      # windows-1252: 0x93/0x94 = “ ” curly quotes, 0x96 = – en dash
      assert String.valid?(subject)
      assert subject == "“Hi” – there"

      # The header must now be encodable by gen_smtp (the delivery path that
      # previously raised); this is a no-op that simply must not crash.
      encoded =
        :mimemail.encode(
          {"text", "plain",
           [{"From", "sender@example.com"}, {"To", "alias@example.com"}, {"Subject", subject}],
           %{}, "hi"}
        )
        |> :erlang.iolist_to_binary()

      assert encoded =~ "Subject: =?UTF-8?"
    end
  end
end
