defmodule Shroud.Email.EmailHandlerTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog
  import Mox

  import Shroud.{AccountsFixtures, AliasesFixtures, DomainFixtures, EmailFixtures}

  alias Shroud.Email
  alias Shroud.Email.EmailHandler
  alias Shroud.{Aliases, Util, Accounts}
  alias ShroudWeb.Router.Helpers, as: Routes

  @html_content """
    <html>
      <body>
        <h1>This is HTML content</h1>
        <p>Lorem ipsum</p>
      </body>
    </html>
  """

  setup do
    user = user_fixture(%{status: :active, email: "user@example.com"})
    email_alias = alias_fixture(%{user_id: user.id, address: "alias@email.shroud.test"})

    %{
      user: user,
      email_alias: email_alias
    }
  end

  describe "perform/1" do
    test "forwards to the correct user", %{user: user, email_alias: email_alias} do
      args = %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          text_email(
            "sender@example.com",
            [email_alias.address],
            "Hello, world",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{email_alias.address, user.email}]

        assert email.from ==
                 {"sender@example.com (via Shroud.email)",
                  "sender_at_example.com_alias@email.shroud.test"}

        assert is_nil(email.reply_to)
      end)
    end

    test "handles emails to multiple recipients", %{user: user, email_alias: email_alias} do
      args = %{
        from: "sender@example.com",
        to: [email_alias.address, "other@example.com"],
        data:
          text_email(
            "sender@example.com",
            [email_alias.address, "other@example.com"],
            "To multiple recipients",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == user.email
      end)

      refute_email_sent(%{to: "other@example.com"})
    end

    test "handles emails to multiple shroud recipients", %{user: user, email_alias: email_alias} do
      %{id: user_id} = other_user = user_fixture(%{status: :active})
      other_alias = alias_fixture(%{user_id: user_id})

      args = %{
        from: "sender@example.com",
        to: [email_alias.address, other_alias.address],
        data:
          text_email(
            "sender@example.com",
            [email_alias.address, other_alias.address],
            "To multiple recipients",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == user.email
      end)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == other_user.email
      end)
    end

    test "transforms reply-to headers to reply addresses", %{user: user} do
      email_alias = alias_fixture(%{address: "myalias@email.shroud.test", user_id: user.id})

      args = %{
        from: "sender@example.com",
        to: [email_alias.address],
        data:
          text_email(
            "sender@example.com",
            [email_alias.address],
            "Custom reply-to!",
            "Plain text content",
            "Reply-To: custom@example.com"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        assert recipient == user.email

        assert email.reply_to ==
                 {"custom_at_example.com_myalias@email.shroud.test",
                  "custom_at_example.com_myalias@email.shroud.test"}
      end)
    end

    test "handles replies from an alias", %{user: user} do
      args = %{
        from: user.email,
        to: ["recipient_at_example.com_alias@email.shroud.test"],
        data:
          text_email(
            user.email,
            ["recipient_at_example.com_alias@email.shroud.test"],
            "To one recipient",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{"recipient@example.com", "recipient@example.com"}]

        assert email.from ==
                 {"alias@email.shroud.test (via Shroud.email)", "alias@email.shroud.test"}

        assert is_nil(email.reply_to)
      end)
    end

    test "ignores replies from non-users" do
      args = %{
        from: "other@example.com",
        to: ["recipient_at_example.com_alias@email.shroud.test"],
        data:
          text_email(
            "other@example.com",
            ["recipient_at_example.com_alias@email.shroud.test"],
            "To one recipient",
            "Plain text content"
          )
      }

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Discarding outgoing email from other@example.com to recipient_at_example.com_alias@email.shroud.test because the alias belongs to someone else"

      assert_no_email_sent()
    end

    test "ignores replies from other users (not the aliases' owner)" do
      other_user = user_fixture()

      args = %{
        from: other_user.email,
        to: ["recipient_at_example.com_alias@email.shroud.test"],
        data:
          text_email(
            other_user.email,
            ["recipient_at_example.com_alias@email.shroud.test"],
            "To one recipient",
            "Plain text content"
          )
      }

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Discarding outgoing email from #{other_user.email} to recipient_at_example.com_alias@email.shroud.test"

      assert_no_email_sent()
    end

    test "does not include reply-to in replies", %{user: user} do
      args = %{
        from: user.email,
        to: ["recipient_at_example.com_alias@email.shroud.test"],
        data:
          text_email(
            user.email,
            ["recipient_at_example.com_alias@email.shroud.test"],
            "To one recipient",
            "Plain text content",
            "Reply-To: #{user.email}"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{"recipient@example.com", "recipient@example.com"}]

        assert email.from ==
                 {"alias@email.shroud.test (via Shroud.email)", "alias@email.shroud.test"}

        assert is_nil(email.reply_to)
      end)
    end

    test "handles existing user emailing other user's alias", %{user: user} do
      other_user = user_fixture()
      other_alias = alias_fixture(%{address: "other@email.shroud.test", user_id: other_user.id})

      args = %{
        from: user.email,
        to: [other_alias.address],
        data:
          text_email(
            user.email,
            [other_alias.address],
            "To one recipient",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.to == [{other_alias.address, other_user.email}]

        assert email.from ==
                 {"#{user.email} (via Shroud.email)",
                  "user_at_example.com_other@email.shroud.test"}

        assert is_nil(email.reply_to)
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

        assert email.from ==
                 {"Sender (via Shroud.email)", "sender_at_example.com_alias@email.shroud.test"}

        assert is_nil(email.reply_to)
        assert email.text_body =~ "Plain text content!"
        assert is_nil(email.html_body)
      end)
    end

    test "handles sender name containing parentheses", %{user: user, email_alias: email_alias} do
      # Sender names with parentheses like "John (Marketing)" can cause RFC 5322 parsing errors
      # when we append " (via Shroud.email)" suffix
      data =
        text_email(
          {"Sender (Marketing)", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}

        # Parentheses should be removed from the sender name to avoid RFC 5322 encoding issues
        assert email.from ==
                 {"Sender Marketing (via Shroud.email)",
                  "sender_at_example.com_alias@email.shroud.test"}

        assert is_nil(email.reply_to)
        assert email.text_body =~ "Plain text content!"
      end)
    end

    test "handles sender name containing double quotes", %{user: user, email_alias: email_alias} do
      # Sender names with double quotes like 'Ash — "Keywords.am"' can cause
      # FunctionClauseError in smtp_util.parse_rfc5322_addresses/1 when mimemail
      # tries to re-encode the headers for SMTP delivery
      data =
        text_email(
          {"Ash \"Keywords.am\"", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}

        # Double quotes should be removed from the sender name to avoid RFC 5322 encoding issues
        assert email.from ==
                 {"Ash Keywords.am (via Shroud.email)",
                  "sender_at_example.com_alias@email.shroud.test"}

        assert is_nil(email.reply_to)
        assert email.text_body =~ "Plain text content!"
      end)
    end

    test "preserves single quotes in sender name", %{user: user, email_alias: email_alias} do
      # Single quotes (apostrophes) are NOT special characters in RFC 5322
      # and should be preserved in sender names like "O'Brien"
      data =
        text_email(
          {"John O'Brien", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {"Recipient", user.email}

        # Single quotes should be preserved
        assert email.from ==
                 {"John O'Brien (via Shroud.email)",
                  "sender_at_example.com_alias@email.shroud.test"}

        assert is_nil(email.reply_to)
        assert email.text_body =~ "Plain text content!"
      end)
    end

    test "handles text/html email", %{user: user, email_alias: email_alias} do
      data = html_email("sender@example.com", [email_alias.address], "HTML only", @html_content)
      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert hd(email.to) == {email_alias.address, user.email}

        assert email.from ==
                 {"sender@example.com (via Shroud.email)",
                  "sender_at_example.com_alias@email.shroud.test"}

        assert is_nil(email.reply_to)
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

        assert email.from ==
                 {"Sender (via Shroud.email)", "sender_at_example.com_alias@email.shroud.test"}

        assert is_nil(email.reply_to)
        assert email.text_body =~ "Plaintext content"
        assert email.html_body =~ "This is HTML content"
      end)
    end

    test "handles unicode email headers (encoded-word)", %{email_alias: email_alias} do
      data =
        text_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Hello, =?utf-8?Q?foo?=",
          "Text body"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.subject == "Hello, foo"
      end)
    end

    test "handles unicode email bodies (quoted-printable)", %{email_alias: email_alias} do
      data =
        text_email(
          {"Sender", "sender@example.com"},
          [{"Recipient", email_alias.address}],
          "Subject",
          "p=C3=A9dagogues",
          "Content-Transfer-Encoding: quoted-printable"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.text_body =~ "pédagogues"
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

    test "forwards to non-active account" do
      yesterday =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1, :day)

      user = user_fixture()
      email_alias = alias_fixture(%{user_id: user.id})

      user
      |> Accounts.User.status_changeset(%{status: :trial, trial_expires_at: yesterday})
      |> Repo.update()

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.text_body =~ "Plain text content!"
      end)
    end

    test "forwards bounces from outgoing emails" do
      user = user_fixture(%{status: :trial})
      email_alias = alias_fixture(%{user_id: user.id, address: "bouncetest@email.shroud.test"})

      data = File.read!("test/support/data/bounce.email") |> Util.lf_to_crlf()

      perform_job(EmailHandler, %{
        from: "MAILER-DAEMON@amazonses.com",
        to: [email_alias.address],
        data: data
      })

      assert_email_sent(fn email ->
        assert email.to == [{email_alias.address, user.email}]

        assert email.from ==
                 {"MAILER-DAEMON@amazonses.com (via Shroud.email)",
                  "MAILER-DAEMON_at_amazonses.com_bouncetest@email.shroud.test"}

        assert email.subject == "Delivery Status Notification (Failure)"

        assert email.text_body =~
                 "The following message to <wrongster@foo.com> was undeliverable."

        assert is_nil(email.html_body)
      end)
    end

    test "does not forward email from a blocked address" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, blocked_addresses: ["sender@example.com"]})

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      assert_no_email_sent()
    end

    test "does not forward when alias is disabled" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, enabled: false})

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      perform_job(EmailHandler, args)

      assert_no_email_sent()
      assert Repo.reload!(email_alias).blocked == 1
    end

    test "does not log by default" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!",
          "X-Spam-Status: No"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) == ""
    end

    test "logs forwarded emails if logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})
      FunWithFlags.enable(:logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Forwarding incoming email from sender@example.com to #{user.email} (via #{email_alias.address})"
    end

    test "logs full email data if verbose logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id})
      FunWithFlags.enable(:email_data_logging, for_actor: user)

      Shroud.MockDateTime
      |> stub(:utc_now_unix, fn ->
        1_656_361_719
      end)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!",
          "Date: Tue, 5 Jul 2022 16:51:05 +0100\nMessage-ID: <deadbeef@local>"
        )

      perform_job(EmailHandler, %{from: "sender@example.com", to: email_alias.address, data: data})

      # Content is Base64 encoded to safely store as JSONB in Oban
      assert_enqueued(
        worker: Shroud.S3.S3UploadJob,
        args: %{
          path: "/emails/sender@example.com-#{email_alias.address}-1656361719.eml",
          content: Base.encode64(data)
        }
      )
    end

    test "does not log incoming emails if not enabled", %{user: user, email_alias: email_alias} do
      FunWithFlags.disable(:email_data_logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Logging test",
          "Plain text content!"
        )

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data: data
      })

      refute_enqueued(worker: Shroud.S3.S3UploadJob)
    end

    test "logs blocked emails if logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, blocked_addresses: ["sender@example.com"]})
      FunWithFlags.enable(:logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Blocking incoming email to #{user.email} because the sender (sender@example.com) is blocked"
    end

    test "logs email to disabled aliases if logging is enabled for user" do
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, enabled: false})
      FunWithFlags.enable(:logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}

      assert capture_log(fn ->
               perform_job(EmailHandler, args)
             end) =~
               "Discarding incoming email from sender@example.com to disabled alias #{email_alias.address}"
    end

    test "handles 554 rejection notices" do
      raw_email = File.read!("test/support/data/554_rejection_notice.email") |> Util.lf_to_crlf()
      perform_job(EmailHandler, %{from: nil, to: "test@test.com", data: raw_email})

      assert_enqueued(worker: Shroud.S3.S3UploadJob)
    end

    test "sends a notice on outgoing spam emails", %{user: user} do
      data =
        text_email(
          user.email,
          ["sender_at_example.com_alias@email.shroud.test"],
          "Text only",
          "Plain text content!",
          "X-Spam-Status: Yes, score=5.1 required=5.0 tests=DKIM_SIGNED,DKIM_VALID,DKIM_VALID_AU,HTML_MESSAGE,RCVD_IN_MSPIKE_H2,SPF_HELO_NONE,SPF_PASS,T_SCC_BODY_TEXT_LINE autolearn=ham autolearn_force=no version=3.4.1"
        )

      perform_job(EmailHandler, %{
        from: user.email,
        to: "sender_at_example.com_alias@email.shroud.test",
        data: data
      })

      assert_enqueued(
        worker: Shroud.Accounts.UserNotifierJob,
        args: %{
          email_function: :deliver_outgoing_email_marked_as_spam,
          email_args: [user.id, "alias@email.shroud.test", "sender@example.com"]
        }
      )

      assert_no_email_sent()
    end

    test "stores incoming spam emails without trackers", %{user: user, email_alias: email_alias} do
      data =
        html_email(
          "spammer@example.com",
          [email_alias.address],
          "Spam email",
          "<h1>Spam</h1><img src=\"https://abc.com/img.jpg\" height=\"1\" width=\"1\" />",
          "X-Spam-Status: Yes, score=5.1 required=5.0 tests=DKIM_SIGNED,DKIM_VALID,DKIM_VALID_AU,HTML_MESSAGE,RCVD_IN_MSPIKE_H2,SPF_HELO_NONE,SPF_PASS,T_SCC_BODY_TEXT_LINE autolearn=ham autolearn_force=no version=3.4.1"
        )

      perform_job(EmailHandler, %{
        from: "spammer@example.com",
        to: email_alias.address,
        data: data
      })

      spam_email = hd(Email.list_spam_emails(user))

      assert spam_email.html_body == "<h1>Spam</h1>"

      assert_enqueued(
        worker: Shroud.Accounts.UserNotifierJob,
        args: %{
          email_function: :deliver_incoming_email_marked_as_spam,
          email_args: [user.id, email_alias.address]
        }
      )

      assert_no_email_sent()
    end

    test "drops emails larger than 25MB", %{user: user, email_alias: email_alias} do
      FunWithFlags.enable(:logging, for_actor: user)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Large email",
          Enum.reduce(1..(25 * 1024 * 1024), "", fn _, acc -> acc <> "." end)
        )

      assert capture_log(fn ->
               perform_job(EmailHandler, %{
                 from: "sender@example.com",
                 to: email_alias.address,
                 data: data
               })
             end) =~
               "Dropping email from sender@example.com to #{email_alias.address} because it's above 25MB"

      assert_no_email_sent()
    end

    test "drops emails (to several recipients) larger than 25MB", %{email_alias: email_alias} do
      data =
        text_email(
          "sender@example.com",
          [email_alias.address, "other@example.com"],
          "Large email",
          Enum.reduce(1..(25 * 1024 * 1024), "", fn _, acc -> acc <> "." end)
        )

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: [email_alias.address, "other@example.com"],
        data: data
      })

      assert_no_email_sent()
    end

    test "creates a new alias if catch-all is enabled", %{user: user} do
      custom_domain = custom_domain_fixture(%{user_id: user.id, catchall_enabled: true})

      data =
        text_email(
          "sender@example.com",
          ["alias@#{custom_domain.domain}"],
          "Catch-all test",
          "Plain text content!"
        )

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: "alias@#{custom_domain.domain}",
        data: data
      })

      email_alias = Aliases.get_email_alias_by_address!("alias@#{custom_domain.domain}")
      metric = Repo.get_by!(Aliases.EmailMetric, alias_id: email_alias.id)

      assert metric.forwarded == 1
      assert email_alias.user_id == user.id
      assert email_alias.enabled
      assert email_alias.notes == "Created by catch-all"
      assert email_alias.forwarded == 1
      assert_email_sent(to: {email_alias.address, user.email}, subject: "Catch-all test")
    end

    test "handles an already-existing alias", %{user: user} do
      custom_domain = custom_domain_fixture(%{user_id: user.id, catchall_enabled: true})

      data =
        text_email(
          "sender@example.com",
          ["alias@#{custom_domain.domain}"],
          "Catch-all test",
          "Plain text content!"
        )

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: "alias@#{custom_domain.domain}",
        data: data
      })

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: "alias@#{custom_domain.domain}",
        data: data
      })

      email_alias = Aliases.get_email_alias_by_address!("alias@#{custom_domain.domain}")
      metric = Repo.get_by!(Aliases.EmailMetric, alias_id: email_alias.id)

      assert metric.forwarded == 2
    end

    test "does not create an alias if catch-all is disabled", %{user: user} do
      custom_domain = custom_domain_fixture(%{user_id: user.id, catchall_enabled: false})

      data =
        text_email(
          "sender@example.com",
          ["alias@#{custom_domain.domain}"],
          "Catch-all test",
          "Plain text content!"
        )

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: "alias@#{custom_domain.domain}",
        data: data
      })

      assert is_nil(Aliases.get_email_alias_by_address("alias@#{custom_domain.domain}"))
      assert_no_email_sent()
    end

    test "adds link to valid email report", %{email_alias: email_alias} do
      data =
        html_email(
          "sender@example.com",
          [email_alias.address],
          "Subject",
          "<p>Body</p>"
        )

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data: data
      })

      expected_report_data =
        %{
          sender: "sender@example.com",
          email_alias: email_alias.address,
          trackers: []
        }
        |> Util.uri_encode_map!()

      expected_url = Routes.page_url(ShroudWeb.Endpoint, :email_report, expected_report_data)

      assert_email_sent(fn email ->
        assert email.html_body =~ expected_url
      end)
    end

    test "handles emails without a To field", %{email_alias: email_alias} do
      data = File.read!("test/support/data/no_to_field.email") |> Util.lf_to_crlf()

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: [email_alias.address],
        data: data
      })
    end

    test "handles emails with no headers", %{email_alias: email_alias} do
      data = File.read!("test/support/data/invalid.email") |> Util.lf_to_crlf()

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: [email_alias.address],
        data: data
      })

      assert_email_sent(fn email ->
        assert email.subject == ""

        assert email.from ==
                 {"sender@example.com (via Shroud.email)",
                  "sender_at_example.com_alias@email.shroud.test"}

        assert email.to == [{"", "user@example.com"}]

        assert email.text_body =~ "just a bunch of text."
        assert email.text_body =~ "forwarded from alias@email.shroud.test"
      end)
    end

    test "handles email data containing non-UTF-8 bytes", %{user: user, email_alias: email_alias} do
      # Email data with raw non-UTF-8 bytes (0xE7 is part of a multi-byte UTF-8 sequence
      # but appears without proper encoding in raw email headers)
      # This simulates real-world emails that have improperly encoded headers
      non_utf8_data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Test subject",
          "Plain text content"
        )
        # Inject raw non-UTF-8 byte sequence into the data
        |> String.replace("Plain text content", "Content with \xE7 invalid byte")

      # Base64 encode the data as SmtpServer.handle_DATA now does
      encoded_data = Base.encode64(non_utf8_data)

      # This should NOT raise Jason.EncodeError when inserting the job
      # The issue is that Oban stores job args as JSONB, and raw email data
      # can contain non-UTF-8 bytes which break JSON encoding
      assert {:ok, job} =
               %{from: "sender@example.com", to: email_alias.address, data: encoded_data}
               |> EmailHandler.new()
               |> Oban.insert()

      assert job.id != nil

      # Drain the queue to process the job
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :outgoing_email)

      # Verify the email was forwarded successfully
      assert_email_sent(fn email ->
        assert hd(email.to) == {email_alias.address, user.email}
      end)
    end

    test "handles legacy jobs with non-Base64 encoded data", %{
      user: user,
      email_alias: email_alias
    } do
      # Legacy jobs (created before Base64 encoding was added) have raw email data.
      # This test ensures backwards compatibility during deployment transition.
      raw_data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Legacy job test",
          "Plain text content"
        )

      # Simulate a legacy job by passing raw (non-Base64) data directly to perform_job
      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data: raw_data
      })

      # Verify the email was forwarded successfully
      assert_email_sent(fn email ->
        assert hd(email.to) == {email_alias.address, user.email}
        assert email.text_body =~ "Plain text content"
      end)
    end
  end

  describe "mailex parsing feature flag" do
    test "uses mimemail by default", %{user: _user, email_alias: email_alias} do
      args = %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          text_email(
            "sender@example.com",
            [email_alias.address],
            "Hello via mimemail",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.subject == "Hello via mimemail"
      end)
    end

    test "uses mailex when flag is enabled for user", %{user: user, email_alias: email_alias} do
      FunWithFlags.enable(:mailex_parsing, for_actor: user)

      args = %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          text_email(
            "sender@example.com",
            [email_alias.address],
            "Hello via mailex",
            "Plain text content"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.subject == "Hello via mailex"
        assert email.text_body =~ "Plain text content"
      end)
    end

    test "uses mailex for multipart emails when flag is enabled", %{
      user: user,
      email_alias: email_alias
    } do
      FunWithFlags.enable(:mailex_parsing, for_actor: user)

      args = %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          multipart_email(
            "sender@example.com",
            [email_alias.address],
            "Multipart via mailex",
            "Text part",
            "<html><body>HTML part</body></html>"
          )
      }

      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        assert email.subject == "Multipart via mailex"
        assert email.text_body =~ "Text part"
        assert email.html_body =~ "HTML part"
      end)
    end
  end
end
