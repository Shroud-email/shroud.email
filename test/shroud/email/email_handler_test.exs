defmodule Shroud.Email.EmailHandlerTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

  import Shroud.{AccountsFixtures, AliasesFixtures, EmailFixtures}

  alias Shroud.Email.EmailHandler
  alias Shroud.Aliases

  @html_content """
    <html>
      <body>
        <h1>This is HTML content</h1>
        <p>Lorem ipsum</p>
      </body>
    </html>
  """

  setup do
    user = user_fixture()
    email_alias = alias_fixture(%{user_id: user.id})

    %{
      user: user,
      email_alias: email_alias
    }
  end

  describe "perform/1" do
    test "logs error if there are multiple recipients" do
      assert capture_log(fn ->
               args = %{from: "sender@e.co", to: ["r1@e.co", "r2@e.co"], data: "data"}
               perform_job(EmailHandler, args)
             end) =~ "Failed to forward"
    end

    test "forwards to the correct user", %{user: user, email_alias: email_alias} do
      args = %{
        from: "sender@example.com",
        to: email_alias.address,
        data: "To: #{email_alias.address}\r\nLorem ipsum"
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == user.email
      end)
    end

    test "handles text/plain email", %{user: user, email_alias: email_alias} do
      data =
        text_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}
        assert email.from == {"Sender (via Shroud)", "noreply@shroud.email"}
        assert email.reply_to == {"Sender", "sender@example.com"}
        assert email.text_body =~ "Plain text content!"
        assert is_nil(email.html_body)
      end)
    end

    test "handles text/html email", %{user: user, email_alias: email_alias} do
      data = html_email("sender@example.com", [email_alias.address], "HTML only", @html_content)
      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {email_alias.address, user.email}
        assert email.from == {"sender@example.com (via Shroud)", "noreply@shroud.email"}
        assert email.reply_to == {"sender@example.com", "sender@example.com"}
        assert is_nil(email.text_body)
        assert email.html_body =~ "This is HTML content"
      end)
    end

    test "handles multipart/alternative email", %{user: user, email_alias: email_alias} do
      data =
        multipart_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Multipart email",
          "Plaintext content",
          @html_content
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}
        assert email.from == {"Sender (via Shroud)", "noreply@shroud.email"}
        assert email.reply_to == {"Sender", "sender@example.com"}
        assert email.text_body =~ "Plaintext content"
        assert email.html_body =~ "This is HTML content"
      end)
    end

    test "increments email metrics", %{email_alias: email_alias} do
      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      metric = Repo.get_by!(Aliases.EmailMetric, alias_id: email_alias.id)
      assert metric.forwarded == 1
    end
  end
end
