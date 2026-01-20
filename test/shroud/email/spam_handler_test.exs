defmodule Shroud.Email.SpamHandlerTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import ExUnit.CaptureLog

  alias Shroud.Email.SpamHandler
  alias Shroud.Email.ReplyAddress
  alias Shroud.Email
  import Shroud.{AccountsFixtures, AliasesFixtures, EmailFixtures}

  describe "spam?/1" do
    test "detects spam emails" do
      email =
        text_email(
          "spammer@example.com",
          ["alias@email.shroud.test"],
          "I want to share my viagra fortune with you",
          "Mountains of viagra, free",
          "X-Spam-Status: Yes, score=5.1 required=5.0 tests=DKIM_SIGNED,DKIM_VALID,DKIM_VALID_AU,HTML_MESSAGE,RCVD_IN_MSPIKE_H2,SPF_HELO_NONE,SPF_PASS,T_SCC_BODY_TEXT_LINE autolearn=ham autolearn_force=no version=3.4.1"
        )

      assert SpamHandler.spam?(email)
    end

    test "detects non-spam emails" do
      email =
        text_email(
          "user@example.com",
          ["alias@email.shroud.test"],
          "My real email",
          "I'm not trying to sell you anything",
          "X-Spam-Status: No, score=-0.1 required=5.0 tests=DKIM_SIGNED,DKIM_VALID,DKIM_VALID_AU,HTML_MESSAGE,RCVD_IN_MSPIKE_H2,SPF_HELO_NONE,SPF_PASS,T_SCC_BODY_TEXT_LINE autolearn=ham autolearn_force=no version=3.4.1"
        )

      refute SpamHandler.spam?(email)
    end

    test "marks email without a SpamAssassin header as not spam" do
      email =
        text_email(
          "sender@example.com",
          ["alias@email.shroud.test"],
          "My subject",
          "Lorem ipsum"
        )

      refute SpamHandler.spam?(email)
    end

    test "logs when it receives an email without a SpamAssassin header" do
      email =
        text_email(
          "sender@example.com",
          ["alias@email.shroud.test"],
          "My subject",
          "Lorem ipsum"
        )

      assert capture_log(fn ->
               SpamHandler.spam?(email)
             end) =~
               "[warning] Received an email from sender@example.com to alias@email.shroud.test without a SpamAssassin header"
    end

    test "handles emails with invalid quoted-printable encoding" do
      # This email has invalid quoted-printable sequences (e.g., =p, =m, =g instead of =XX hex)
      # which would cause :mimemail.decode to throw :badchar
      email =
        invalid_quoted_printable_email(
          "sender@example.com",
          ["alias@email.shroud.test"],
          "Test Subject",
          "X-Spam-Status: Yes, score=5.1 required=5.0 tests=TEST autolearn=ham version=3.4.1"
        )

      # Should not crash, and should detect spam from the header
      assert SpamHandler.spam?(email)
    end

    test "handles non-spam emails with invalid quoted-printable encoding" do
      email =
        invalid_quoted_printable_email(
          "sender@example.com",
          ["alias@email.shroud.test"],
          "Test Subject",
          "X-Spam-Status: No, score=-1.0 required=5.0 tests=TEST autolearn=ham version=3.4.1"
        )

      # Should not crash, and should detect as not spam
      refute SpamHandler.spam?(email)
    end
  end

  describe "get_spamassassin_header/1" do
    test "extracts the SpamAssassin header from an email" do
      spam_header =
        "Yes, score=5.1 required=5.0 tests=DKIM_SIGNED,DKIM_VALID autolearn=ham version=3.4.1"

      email =
        text_email(
          "sender@example.com",
          ["alias@shroud.test"],
          "Test Subject",
          "Test Content",
          "X-Spam-Status: #{spam_header}"
        )
        |> :mimemail.decode()

      assert SpamHandler.get_spamassassin_header(email) == spam_header
    end

    test "returns an empty string when no SpamAssassin header is present" do
      email =
        text_email(
          "sender@example.com",
          ["alias@shroud.test"],
          "Test Subject",
          "Test Content"
        )
        |> :mimemail.decode()

      assert capture_log(fn ->
               assert SpamHandler.get_spamassassin_header(email) == ""
             end) =~ "without a SpamAssassin header"
    end
  end

  describe "handle_outgoing_spam_email/1" do
    setup do
      user = user_fixture()
      email_alias = alias_fixture(%{user_id: user.id})
      %{user: user, email_alias: email_alias}
    end

    test "enqueues a job to email notify the user", %{user: user, email_alias: email_alias} do
      reply_address = ReplyAddress.to_reply_address("recipient@example.com", email_alias.address)

      email =
        text_email(
          user.email,
          [reply_address],
          "My subject",
          "Lorem ipsum"
        )
        |> :mimemail.decode()

      assert :ok == SpamHandler.handle_outgoing_spam_email(email)

      assert_enqueued(
        worker: Shroud.Accounts.UserNotifierJob,
        args: %{
          email_function: :deliver_outgoing_email_marked_as_spam,
          email_args: [user.id, email_alias.address, "recipient@example.com"]
        }
      )
    end
  end

  describe "handle_incoming_spam_email/4" do
    setup do
      user = user_fixture()
      email_alias = alias_fixture(%{user_id: user.id})
      %{user: user, email_alias: email_alias}
    end

    test "stores spam email with the SpamAssassin header", %{user: user, email_alias: email_alias} do
      spam_header =
        "Yes, score=5.1 required=5.0 tests=DKIM_SIGNED,DKIM_VALID autolearn=ham version=3.4.1"

      email =
        text_email(
          "spammer@example.com",
          [email_alias.address],
          "Spam Subject",
          "Spam Content",
          "X-Spam-Status: #{spam_header}"
        )
        |> :mimemail.decode()

      :ok =
        SpamHandler.handle_incoming_spam_email("spammer@example.com", user, email_alias, email)

      # Get the latest spam email for this user
      spam_emails = Email.list_spam_emails(user)
      assert length(spam_emails) > 0

      # Get the most recently created spam email
      spam_email = Enum.max_by(spam_emails, & &1.inserted_at)

      # Verify the SpamAssassin header was stored
      assert spam_email.spamassassin_header == spam_header
      assert spam_email.from == "spammer@example.com"
      assert spam_email.subject == "Spam Subject"

      assert_enqueued(
        worker: Shroud.Accounts.UserNotifierJob,
        args: %{
          email_function: :deliver_incoming_email_marked_as_spam,
          email_args: [user.id, email_alias.address]
        }
      )
    end
  end
end
