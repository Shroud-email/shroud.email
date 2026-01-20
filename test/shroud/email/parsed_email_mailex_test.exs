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
  end
end
