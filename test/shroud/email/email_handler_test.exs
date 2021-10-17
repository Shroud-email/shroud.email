defmodule Shroud.Email.EmailHandlerTest do
  use Shroud.DataCase, async: true
  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

  import Shroud.AccountsFixtures
  import Shroud.AliasesFixtures

  alias Shroud.Email.EmailHandler

  setup do
    user = user_fixture()
    email_alias = alias_fixture(%{user_id: user.id})

    %{
      user: user,
      email_alias: email_alias
    }
  end

  describe "forward_email/3" do
    test "logs error if there are multiple recipients" do
      assert capture_log(fn ->
               EmailHandler.forward_email("sender@e.co", ["r1@e.co", "r2@e.co"], "data")
             end) =~ "Failed to forward"
    end

    test "forwards to the correct user", %{user: user, email_alias: email_alias} do
      EmailHandler.forward_email("sender@example.com", [email_alias.address], "lorem ipsum")

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == user.email
      end)
    end

    test "handles text/plain email", %{user: user, email_alias: email_alias} do
      data = File.read!("test/support/data/plaintext.email")
      EmailHandler.forward_email("sender@example.com", [email_alias.address], data)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}
        assert email.from == {"Sender (via Shroud)", "noreply@shroud.email"}
        assert email.reply_to == {"Sender", "sender@example.com"}
        assert email.text_body =~ "Plain text email goes here!"
        assert is_nil(email.html_body)
        assert email.headers["content-type"] =~ "text/plain"
      end)
    end

    test "handles text/html email", %{user: user, email_alias: email_alias} do
      data = File.read!("test/support/data/html.email")
      EmailHandler.forward_email("sender@example.com", [email_alias.address], data)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}
        assert email.from == {"Sender (via Shroud)", "noreply@shroud.email"}
        assert email.reply_to == {"Sender", "sender@example.com"}
        assert is_nil(email.text_body)
        assert email.html_body =~ "This is the HTML Section"
        assert email.headers["content-type"] =~ "text/HTML"
      end)
    end

    test "handles multipart/alternative email", %{user: user, email_alias: email_alias} do
      data = File.read!("test/support/data/multipart.email")
      EmailHandler.forward_email("sender@example.com", [email_alias.address], data)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}
        assert email.from == {"Sender (via Shroud)", "noreply@shroud.email"}
        assert email.reply_to == {"Sender", "sender@example.com"}
        assert email.text_body =~ "Plain text email goes here!"
        assert email.html_body =~ "This is the HTML Section"
        assert email.headers["content-type"] =~ "multipart/alternative"
      end)
    end
  end
end
