defmodule Shroud.Email.EmailHandlerTest.FailingMailerAdapter do
  @moduledoc "Test-only Swoosh adapter that fails all deliveries or a selected recipient."
  @behaviour Swoosh.Adapter
  alias Swoosh.Adapters.Test

  @impl true
  def deliver(email, config) do
    if is_nil(config[:fail_to]) or Enum.any?(email.to, fn {_, to} -> to == config[:fail_to] end) do
      {:error, Keyword.get(config, :reason, :simulated_smtp_failure)}
    else
      Test.deliver(email, [])
    end
  end

  @impl true
  def validate_config(_config), do: :ok
end

defmodule Shroud.Email.EmailHandlerTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog
  import Mox

  import Shroud.{
    AccountsFixtures,
    AliasesFixtures,
    DomainFixtures,
    EmailFixtures,
    TrackerFixtures
  }

  alias Shroud.Repo
  alias Shroud.Email
  alias Shroud.Email.{EmailHandler, ParsedEmail, TrackerDomain}
  alias Shroud.Email.EmailHandlerTest.FailingMailerAdapter
  alias Shroud.{Aliases, Util, Accounts}
  alias Swoosh.Adapters.SMTP.Helpers
  use ShroudWeb, :verified_routes

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
    test "logs structured delivery errors and returns them without counting a delivery", %{
      user: user,
      email_alias: email_alias
    } do
      Sentry.Test.setup_sentry()

      smtp_error =
        {:permanent_failure, ~c"haraka", "501 RFC-5321 local-part exceeds 64 octets\r\n"}

      incoming_args = tracking_pixel_email_args(email_alias)

      outgoing_args = %{
        from: user.email,
        to: "recipient_at_example.com_alias@email.shroud.test",
        data: text_email(user.email, ["recipient@example.com"], "Reply", "Hello")
      }

      for args <- [incoming_args, outgoing_args],
          reason <- [smtp_error, {:retries_exceeded, smtp_error}, {501, %{"error" => smtp_error}}] do
        job = args |> EmailHandler.new() |> Oban.insert!() |> Repo.reload!()

        log =
          capture_log(fn ->
            with_failing_mailer(
              fn -> assert {:error, ^smtp_error} = EmailHandler.perform(job) end,
              reason: reason
            )
          end)

        assert log =~ "permanent_failure"
        assert log =~ "local-part exceeds 64 octets"
        assert [event] = Sentry.Test.pop_sentry_reports()
        assert event.source == :logger
        assert event.extra.logger_metadata[:oban_job_id] == job.id
      end

      email_alias = Aliases.get_email_alias_by_address!(email_alias.address)
      assert email_alias.forwarded == 0
      assert email_alias.replied == 0
      assert Repo.aggregate(TrackerDomain, :count) == 0
      refute_enqueued(worker: Shroud.Email.ImageFetcher)
      assert_no_email_sent()
    end

    test "visits normal images and removed trackers without restoring them in delivered HTML", %{
      email_alias: email_alias
    } do
      tracker_fixture(%{name: "Known tracker", pattern: "https://known\\.example\\.com/"})

      data =
        html_email("sender@example.com", [email_alias.address], "Images", """
        <img src="https://images.example.com/photo.jpg">
        <img src="https://known.example.com/open">
        <img src="https://unknown.example.com/pixel" width="1" height="1">
        """)

      assert :ok =
               perform_job(EmailHandler, %{
                 from: "sender@example.com",
                 to: email_alias.address,
                 data: data
               })

      assert_email_sent(fn email ->
        assert length(Floki.find(Floki.parse_document!(email.html_body), "img")) == 1
        refute email.html_body =~ "known.example.com"
        refute email.html_body =~ "unknown.example.com"
        assert email.html_body =~ "/proxy?"
      end)

      urls =
        all_enqueued(worker: Shroud.Email.ImageFetcher)
        |> Enum.map(& &1.args["url"])
        |> Enum.sort()

      assert urls == [
               "https://images.example.com/photo.jpg",
               "https://known.example.com/open",
               "https://unknown.example.com/pixel"
             ]
    end

    test "disabling branding removes both footers without disabling tracker removal", %{
      user: user,
      email_alias: email_alias
    } do
      {:ok, _} = Accounts.update_user_email_preferences(user, %{email_branding: false})

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          multipart_email(
            {"Alice", "sender@example.com"},
            [email_alias.address],
            "Without branding",
            "Plain text content",
            ~s(<html><body><p>HTML content</p><img src="https://spy.example.com/pixel" width="1" height="1" /></body></html>)
          )
      })

      assert_email_sent(fn email ->
        assert email.from == {"Alice", "sender_at_example.com_alias@email.shroud.test"}
        assert email.to == [{email_alias.address, user.email}]
        assert String.trim(email.text_body) == "Plain text content"
        refute email.html_body =~ "spy.example.com"
        refute email.html_body =~ "Shroud.email"
        refute email.html_body =~ "/email-report/"
        assert email.html_body =~ "HTML content"
      end)

      assert %TrackerDomain{count: 1} =
               Repo.get_by(TrackerDomain, domain: "spy.example.com", date: Date.utc_today())

      assert Aliases.get_email_alias_by_address!(email_alias.address).forwarded == 1
    end

    test "disabling branding keeps fallback sender names and private reply-to routing", %{
      user: user,
      email_alias: email_alias
    } do
      {:ok, _} = Accounts.update_user_email_preferences(user, %{email_branding: false})

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          text_email(
            "sender@example.com",
            [email_alias.address],
            "Without branding",
            "Plain text content",
            "Reply-To: custom@example.com"
          )
      })

      assert_email_sent(fn email ->
        assert email.from ==
                 {"sender@example.com", "sender_at_example.com_alias@email.shroud.test"}

        assert email.reply_to ==
                 {"custom_at_example.com_alias@email.shroud.test",
                  "custom_at_example.com_alias@email.shroud.test"}
      end)
    end

    test "outgoing replies omit branding when disabled without leaking the real address", %{
      user: user,
      email_alias: email_alias
    } do
      {:ok, _} = Accounts.update_user_email_preferences(user, %{email_branding: false})
      reply_address = "recipient_at_example.com_alias@email.shroud.test"

      perform_job(EmailHandler, %{
        from: user.email,
        to: reply_address,
        data:
          text_email(
            {"Real name", user.email},
            [reply_address],
            "Reply without branding",
            "Reply content",
            "Reply-To: #{user.email}"
          )
      })

      assert_email_sent(fn email ->
        assert email.from == {email_alias.address, email_alias.address}
        assert email.to == [{"recipient@example.com", "recipient@example.com"}]
        assert is_nil(email.reply_to)
        assert String.trim(email.text_body) == "Reply content"
      end)

      assert Aliases.get_email_alias_by_address!(email_alias.address).replied == 1
    end

    test "enabling branding restores incoming and outgoing branding after a saved opt-out",
         %{
           user: user,
           email_alias: email_alias
         } do
      {:ok, user} = Accounts.update_user_email_preferences(user, %{email_branding: false})
      {:ok, _} = Accounts.update_user_email_preferences(user, %{email_branding: true})

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data:
          multipart_email(
            "sender@example.com",
            [email_alias.address],
            "Incoming with branding",
            "Plain text content",
            "<p>HTML content</p>"
          )
      })

      assert_email_sent(fn email ->
        assert email.from ==
                 {"sender@example.com (via Shroud.email)",
                  "sender_at_example.com_alias@email.shroud.test"}

        assert email.text_body =~ "forwarded from #{email_alias.address} by Shroud.email"
        assert email.html_body =~ "forwarded by Shroud.email"
      end)

      reply_address = "recipient_at_example.com_alias@email.shroud.test"

      perform_job(EmailHandler, %{
        from: user.email,
        to: reply_address,
        data: text_email(user.email, [reply_address], "Reply after rollback", "Reply content")
      })

      assert_email_sent(fn email ->
        assert email.from == {"#{email_alias.address} (via Shroud.email)", email_alias.address}
      end)
    end

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

    test "uses the alias as SMTP envelope sender when the reply address exceeds 64 bytes", %{
      user: user
    } do
      email_alias =
        alias_fixture(%{user_id: user.id, address: "qr9frrxbqzyv15j@email.shroud.test"})

      sender = "noreply-feedcoyote-ncej243@no-reply.feedcoyote.com"

      assert :ok =
               perform_job(EmailHandler, %{
                 from: sender,
                 to: email_alias.address,
                 data:
                   text_email(
                     sender,
                     [email_alias.address],
                     "Long sender address",
                     "Hello",
                     "Reply-To: support@example.com"
                   )
               })

      assert_email_sent(fn email ->
        assert Helpers.sender(email) == email_alias.address
        assert email.to == [{email_alias.address, user.email}]

        assert email.from ==
                 {"#{sender} (via Shroud.email)",
                  "noreply-feedcoyote-ncej243_at_no-reply.feedcoyote.com_qr9frrxbqzyv15j@email.shroud.test"}

        reply_to = "support_at_example.com_qr9frrxbqzyv15j@email.shroud.test"
        assert email.reply_to == {reply_to, reply_to}
        assert is_binary(Helpers.body(email, []))
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

      assert {:ok, _} = args |> EmailHandler.new() |> Oban.insert()

      assert %{success: 3, failure: 0} =
               Oban.drain_queue(queue: :outgoing_email, with_recursion: true)

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

      assert {:ok, _} = args |> EmailHandler.new() |> Oban.insert()

      assert %{success: 3, failure: 0} =
               Oban.drain_queue(queue: :outgoing_email, with_recursion: true)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == user.email
      end)

      assert_email_sent(fn email ->
        {_name, recipient} = hd(email.to)
        recipient == other_user.email
      end)
    end

    test "a one-element recipient list uses fan-out before delivery", %{
      user: user,
      email_alias: email_alias
    } do
      args = %{tracking_pixel_email_args(email_alias) | to: [email_alias.address]}
      assert {:ok, _} = args |> EmailHandler.new() |> Oban.insert()

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :outgoing_email)
      assert_no_email_sent()
      assert_enqueued(worker: EmailHandler, args: %{to: email_alias.address})

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :outgoing_email)
      assert_email_sent(fn email -> hd(email.to) |> elem(1) == user.email end)
      assert_no_email_sent()
      assert Aliases.get_email_alias_by_address!(email_alias.address).forwarded == 1
    end

    test "retries only the failed recipient after a partial delivery failure", %{
      user: user,
      email_alias: email_alias
    } do
      other_user = user_fixture(%{status: :active})
      user_email = user.email
      other_email = other_user.email
      other_alias = alias_fixture(%{user_id: other_user.id})
      args = tracking_pixel_email_args(email_alias)
      args = %{args | to: [email_alias.address, other_alias.address]}
      assert {:ok, parent} = args |> EmailHandler.new() |> Oban.insert()
      parent = Repo.get!(Oban.Job, parent.id)
      jobs = from j in Oban.Job, where: j.queue == "outgoing_email"

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :outgoing_email)
      assert_no_email_sent()

      capture_log(fn ->
        with_failing_mailer(
          fn ->
            assert %{success: 1, failure: 1} = Oban.drain_queue(queue: :outgoing_email)
          end,
          fail_to: other_user.email
        )
      end)

      assert_email_sent(fn email -> hd(email.to) |> elem(1) == user_email end)
      refute_received {:email, %{to: [{_, ^other_email}]}}
      assert Aliases.get_email_alias_by_address!(email_alias.address).forwarded == 1
      assert Aliases.get_email_alias_by_address!(other_alias.address).forwarded == 0
      assert %TrackerDomain{count: 1} = Repo.get_by!(TrackerDomain, domain: "spy.example.com")

      # Replay even a stale parent struct: no duplicate children may be created.
      assert :ok = EmailHandler.perform(parent)
      assert Repo.aggregate(jobs, :count) == 3

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :outgoing_email, with_scheduled: true)

      assert_email_sent(fn email -> hd(email.to) |> elem(1) == other_email end)
      assert_no_email_sent()
      assert Aliases.get_email_alias_by_address!(email_alias.address).forwarded == 1
      assert Aliases.get_email_alias_by_address!(other_alias.address).forwarded == 1
      assert %TrackerDomain{count: 2} = Repo.get_by!(TrackerDomain, domain: "spy.example.com")

      # Pruning completed children must not make a parent retry fan out again.
      Repo.delete_all(from j in jobs, where: j.id != ^parent.id)
      assert :ok = EmailHandler.perform(parent)
      assert Repo.aggregate(jobs, :count) == 1
      assert_no_email_sent()
    end

    test "fan-out deduplicates envelope recipients and preserves binary email data", %{
      email_alias: email_alias
    } do
      data = "Raw email with invalid UTF-8: \xE7"
      recipients = [email_alias.address, "other@example.com", email_alias.address]

      assert {:ok, parent} =
               %{from: "sender@example.com", to: recipients, data: Base.encode64(data)}
               |> EmailHandler.new(meta: %{existing: "preserved"})
               |> Oban.insert()

      parent = Repo.get!(Oban.Job, parent.id)
      assert :ok = EmailHandler.perform(parent)

      children =
        Repo.all(from j in Oban.Job, where: j.queue == "outgoing_email" and j.id != ^parent.id)

      assert Enum.sort(Enum.map(children, & &1.args["to"])) == Enum.sort(Enum.uniq(recipients))
      assert Enum.all?(children, &(&1.args["data"] == Base.encode64(data)))

      assert Repo.get!(Oban.Job, parent.id).meta ==
               %{"existing" => "preserved", "fan_out_completed" => true}

      assert_no_email_sent()
    end

    test "a failed fan-out transaction rolls back children and can be retried", %{
      email_alias: email_alias
    } do
      args = %{
        tracking_pixel_email_args(email_alias)
        | to: [email_alias.address, "other@example.com"]
      }

      assert {:ok, parent} = args |> EmailHandler.new() |> Oban.insert()
      parent = Repo.get!(Oban.Job, parent.id)
      jobs = from j in Oban.Job, where: j.queue == "outgoing_email"

      # Fail the marker write, after child insertion, to exercise atomicity.
      Repo.query!("""
      ALTER TABLE oban_jobs ADD CONSTRAINT reject_fan_out_marker
      CHECK (NOT (meta ? 'fan_out_completed'))
      """)

      assert_raise Ecto.ConstraintError, fn -> EmailHandler.perform(parent) end
      assert Repo.aggregate(jobs, :count) == 1
      refute Repo.get!(Oban.Job, parent.id).meta["fan_out_completed"]

      Repo.query!("ALTER TABLE oban_jobs DROP CONSTRAINT reject_fan_out_marker")
      assert :ok = EmailHandler.perform(parent)
      assert Repo.aggregate(jobs, :count) == 3
      assert_no_email_sent()
    end

    test "failed reply deliveries are returned to Oban", %{user: user} do
      args = %{
        from: user.email,
        to: "recipient_at_example.com_alias@email.shroud.test",
        data: text_email(user.email, ["recipient@example.com"], "Reply", "Hello")
      }

      capture_log(fn ->
        with_failing_mailer(fn ->
          assert {:error, :simulated_smtp_failure} = perform_job(EmailHandler, args)
        end)
      end)

      assert Aliases.get_email_alias_by_address!("alias@email.shroud.test").replied == 0
    end

    test "transforms reply-to headers to reply addresses", %{user: user} do
      email_alias = alias_fixture(%{address: "myalias@email.shroud.test", user_id: user.id})

      args = %{
        from: "sender@example.com",
        to: email_alias.address,
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
        to: "recipient_at_example.com_alias@email.shroud.test",
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
        to: "recipient_at_example.com_alias@email.shroud.test",
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
               "Discarding outgoing email from other@example.com to recipient_at_example.com_alias@email.shroud.test because user is not on a paid plan"

      assert_no_email_sent()
    end

    test "ignores replies from other users (not the aliases' owner)" do
      other_user = user_fixture()

      args = %{
        from: other_user.email,
        to: "recipient_at_example.com_alias@email.shroud.test",
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
        to: "recipient_at_example.com_alias@email.shroud.test",
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
        to: other_alias.address,
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

    test "handles a sender address with a quoted name but no angle brackets", %{
      user: user,
      email_alias: email_alias
    } do
      # Some emails have a malformed "From" header with a quoted display name
      # but no angle brackets, e.g. `From: "Sales Team" promo@example.com`. This parses
      # into an address of `"Sales Team"promo@example.com` (quotes retained). The address
      # then feeds the outgoing reply address, and mimemail crashes while encoding the
      # `From` header with {:error, {1, :smtp_rfc5322_scan, {:illegal, ~c"\"\""}}}.
      data =
        text_email(
          ~s("Sales Team" promo@example.com),
          [{"Recipient", email_alias.address}],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "promo@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {_name, from_address} = email.from
        # The outgoing address must not contain double quotes, otherwise encoding fails.
        refute from_address =~ ~s(")

        # Faithfully reproduce the production crash: encoding the forwarded email
        # for SMTP delivery must not raise.
        assert is_binary(Swoosh.Adapters.SMTP.Helpers.body(email, []))
      end)
    end

    test "handles a recipient address with a quoted name but no angle brackets", %{
      user: user,
      email_alias: email_alias
    } do
      # A malformed "To" header with a quoted display name but no angle brackets, e.g.
      # `To: "Subscriber" alias@email.shroud.test`, parses into an address (and display
      # name) containing double quotes. Those quotes must be stripped so the forwarded
      # email can be encoded for delivery.
      malformed_recipient = ~s("Subscriber" #{email_alias.address})

      data =
        text_email(
          {"Sender", "sender@example.com"},
          [malformed_recipient],
          "Text only",
          "Plain text content!"
        )

      args = %{from: "sender@example.com", to: email_alias.address, data: data}
      perform_job(EmailHandler, args)

      assert_email_sent(fn email ->
        {recipient_name, recipient_address} = hd(email.to)
        assert recipient_address == user.email
        refute recipient_name =~ ~s(")

        assert is_binary(Swoosh.Adapters.SMTP.Helpers.body(email, []))
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

    test "forwards terminal quoted-printable soft breaks without stray equals signs", %{
      user: user,
      email_alias: email_alias
    } do
      {:ok, _} = Accounts.update_user_email_preferences(user, %{email_branding: false})

      data =
        """
        From: sender@example.com
        To: #{email_alias.address}
        Subject: Soft breaks
        Content-Type: multipart/mixed; boundary=outer

        --outer
        Content-Type: multipart/alternative; boundary=inner

        --inner
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Total=3D=
        --inner
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        <html><body><p>Total=3D</p></body></html>=
        --inner--
        --outer--
        """
        |> Util.lf_to_crlf()

      assert :ok =
               perform_job(EmailHandler, %{
                 from: "sender@example.com",
                 to: email_alias.address,
                 data: data
               })

      assert_email_sent(fn email ->
        assert email.text_body == "Total="
        assert email.html_body == "<html><body><p>Total=</p></body></html>"

        delivered =
          email
          |> Helpers.body([])
          |> Mailex.parse!()
          |> ParsedEmail.parse("sender@example.com", user.email)

        assert delivered.swoosh_email.text_body == email.text_body
        assert delivered.swoosh_email.html_body == email.html_body
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
      user = user_fixture()
      email_alias = alias_fixture(%{user_id: user.id})

      user
      |> Accounts.User.status_changeset(%{status: :inactive})
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

    test "archives malformed bounce MIME without raising or notifying", %{
      email_alias: email_alias,
      user: user
    } do
      Sentry.Test.setup_sentry(dedup_events: false)

      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from(email_alias.address)
        |> Swoosh.Email.to("recipient@example.org")
        |> Swoosh.Email.subject("Original subject")
        |> Swoosh.Email.text_body("Private body")
        |> Shroud.Email.DeliveryMarker.attach(
          "outgoing",
          user,
          email_alias.address,
          "recipient@example.org"
        )

      for original_format <- [:headers, :full],
          report = delivery_status_report(email, original_format: original_format),
          data <- [
            String.replace(
              report,
              "Content-Type: multipart/report;",
              "Content-Type: multipart/report; name*=UTF-8''%GG;"
            ),
            String.replace(
              report,
              "Content-Type: text/plain",
              "Content-Type: text/plain; name*=UTF-8''%GG"
            ),
            String.replace(
              report,
              "Subject: Original subject\r\n",
              "Subject: Original subject\r\nContent-Disposition: attachment; filename*=UTF-8''%GG\r\n"
            )
          ],
          from <- ["", "MAILER-DAEMON@example.net"] do
        assert :ok = perform_job(EmailHandler, %{from: from, to: email_alias.address, data: data})
        assert_no_email_sent()
        assert [event] = Sentry.Test.pop_sentry_reports()
        assert event.fingerprint == ["shroud-unclassified-email-bounce"]

        assert_enqueued(
          worker: Shroud.S3.S3UploadJob,
          args: %{content: data, path: event.extra.s3_path}
        )
      end

      refute_enqueued(worker: Shroud.Accounts.UserNotifierJob)
    end

    test "notifies the sender of an authenticated outgoing bounce with a non-null sender" do
      Sentry.Test.setup_sentry(dedup_events: false)
      user = user_fixture(%{status: :active})
      email_alias = alias_fixture(%{user_id: user.id, address: "bouncetest@email.shroud.test"})

      assert :ok =
               perform_job(EmailHandler, %{
                 from: user.email,
                 to: "wrongster_at_foo.com_bouncetest@email.shroud.test",
                 data:
                   text_email(
                     user.email,
                     ["wrongster@foo.com"],
                     "=?UTF-8?B?#{Base.encode64("Private subject — café")}?=",
                     "Private body"
                   )
               })

      assert_received {:email, outgoing}
      marker = outgoing.headers["X-Shroud-Delivery"]
      refute marker =~ user.email
      refute marker =~ email_alias.address
      refute marker =~ "wrongster@foo.com"

      data = delivery_status_report(outgoing, original_format: :full)

      perform_job(EmailHandler, %{
        from: "MAILER-DAEMON@amazonses.com",
        to: email_alias.address,
        data: data
      })

      assert_no_email_sent()
      assert [job] = all_enqueued(worker: Shroud.Accounts.UserNotifierJob)
      assert {:ok, _email} = perform_job(Shroud.Accounts.UserNotifierJob, job.args)

      assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.from == {"Shroud.email", "noreply@email.shroud.test"}
        assert email.subject == "Your email was not delivered"
        assert email.text_body =~ "wrongster@foo.com via #{email_alias.address}"
        assert email.text_body =~ "Subject: Private subject — café"
        assert email.text_body =~ "The recipient's address was rejected."
        refute email.text_body =~ "Private body"
        refute email.text_body =~ "malicious.example"
        refute email.text_body =~ "private diagnostic"
        refute Map.has_key?(email.headers, "X-Shroud-Delivery")
        assert email.headers["Auto-Submitted"] == "auto-generated"

        html_text = email.html_body |> Floki.parse_document!() |> Floki.text()
        assert html_text =~ "wrongster@foo.com via #{email_alias.address}"
        assert html_text =~ "Subject: Private subject — café"
        assert html_text =~ "The recipient's address was rejected."
        refute html_text =~ "Private body"
        refute html_text =~ "private diagnostic"
        assert html_text =~ "Delivery status: 5.1.1"
      end)

      assert [] = Sentry.Test.pop_sentry_reports()
      assert_enqueued(worker: Shroud.S3.S3UploadJob, args: %{content: data})
    end

    test "reports inbox-forwarding failures without emailing the rejecting inbox", %{
      email_alias: email_alias,
      user: user
    } do
      Sentry.Test.setup_sentry(dedup_events: false)

      assert :ok =
               perform_job(EmailHandler, %{
                 from: "sender@example.net",
                 to: email_alias.address,
                 data:
                   text_email(
                     "sender@example.net",
                     [email_alias.address],
                     "Incoming",
                     "Private body"
                   )
               })

      assert_received {:email, incoming}
      Sentry.Context.set_user_context(%{email: user.email})
      Sentry.Context.set_extra_context(%{recipient: user.email, oban_job_id: 123})
      Sentry.Context.add_breadcrumb(message: "Private body")

      assert :ok =
               perform_job(EmailHandler, %{
                 from: "",
                 to: email_alias.address,
                 data: delivery_status_report(incoming, status: "5.2.2")
               })

      assert_no_email_sent()
      assert [event] = Sentry.Test.pop_sentry_reports()
      assert event.fingerprint == ["shroud-incoming-forwarding-bounce"]
      assert event.tags == %{delivery_status: "5.2.2"}
      assert [upload] = all_enqueued(worker: Shroud.S3.S3UploadJob)
      assert event.extra == %{s3_path: upload.args["path"]}
      assert event.user == %{}
      assert event.breadcrumbs == []
      assert event.contexts == nil
      assert event.request == %Sentry.Interfaces.Request{}
      refute_enqueued(worker: Shroud.Accounts.UserNotifierJob)
    end

    test "returns notification delivery failures to Oban for retry", %{
      email_alias: email_alias,
      user: user
    } do
      Sentry.Test.setup_sentry(dedup_events: false)

      perform_job(EmailHandler, %{
        from: user.email,
        to: "recipient_at_example.org_alias@email.shroud.test",
        data: text_email(user.email, ["recipient@example.org"], "Outgoing", "Private body")
      })

      assert_received {:email, outgoing}

      log =
        capture_log(fn ->
          with_failing_mailer(
            fn ->
              assert :ok =
                       perform_job(EmailHandler, %{
                         from: "",
                         to: email_alias.address,
                         data: delivery_status_report(outgoing)
                       })

              assert [job] = all_enqueued(worker: Shroud.Accounts.UserNotifierJob)

              assert {:error, reason} = perform_job(Shroud.Accounts.UserNotifierJob, job.args)
              assert reason == "Private failure for #{user.email}"
            end,
            reason: "Private failure for #{user.email}"
          )
        end)

      refute log =~ user.email
      refute log =~ "Private failure"
      assert_no_email_sent()
      assert [] = Sentry.Test.pop_sentry_reports()
      assert_enqueued(worker: Shroud.S3.S3UploadJob)
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

    test "reports bounces in one Sentry issue with their archive paths", %{
      email_alias: email_alias
    } do
      Sentry.Test.setup_sentry(dedup_events: false)
      Sentry.Context.set_user_context(%{email: "private@example.com"})
      Sentry.Context.set_extra_context(%{recipient: email_alias.address, oban_job_id: 123})
      Sentry.Context.set_tags_context(%{sender: "private@example.com"})
      Sentry.Context.set_request_context(%{data: "private message"})
      Sentry.Context.add_breadcrumb(message: "private message")

      raw_email = File.read!("test/support/data/554_rejection_notice.email") |> Util.lf_to_crlf()

      for {from, to, data} <- [
            {"", email_alias.address, raw_email},
            {nil, "other@email.shroud.test", "Subject: Private subject\r\n\r\nPrivate body"}
          ] do
        assert :ok = perform_job(EmailHandler, %{from: from, to: to, data: data})

        assert [event] = Sentry.Test.pop_sentry_reports()
        assert event.message.formatted == "Received an unclassified email bounce report"
        assert event.level == :warning
        assert event.fingerprint == ["shroud-unclassified-email-bounce"]

        upload =
          Enum.find(all_enqueued(worker: Shroud.S3.S3UploadJob), &(&1.args["content"] == data))

        assert upload.args["path"] =~ "/bounces/#{to}-"

        assert event == %Sentry.Event{
                 event_id: event.event_id,
                 timestamp: event.timestamp,
                 environment: event.environment,
                 release: event.release,
                 message: event.message,
                 level: :warning,
                 fingerprint: ["shroud-unclassified-email-bounce"],
                 extra: %{s3_path: upload.args["path"]}
               }
      end

      assert_no_email_sent()
    end

    test "discards outgoing email from free users" do
      free_user = user_fixture(%{status: :free, email: "freeuser@example.com"})

      _free_alias =
        alias_fixture(%{user_id: free_user.id, address: "freealias@email.shroud.test"})

      data =
        text_email(
          free_user.email,
          ["sender_at_example.com_freealias@email.shroud.test"],
          "Text only",
          "Plain text content!"
        )

      assert capture_log(fn ->
               perform_job(EmailHandler, %{
                 from: free_user.email,
                 to: "sender_at_example.com_freealias@email.shroud.test",
                 data: data
               })
             end) =~ "not on a paid plan"

      assert_no_email_sent()
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
      refute_enqueued(worker: Shroud.Email.ImageFetcher)

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

    @tag :catchall_invalid
    test "attaches a non-spam message when a catch-all address is invalid", %{user: user} do
      custom_domain = custom_domain_fixture(%{user_id: user.id, catchall_enabled: true})
      invalid_address = "invalid_address@#{custom_domain.domain}"

      data =
        text_email(
          "sender@example.com",
          [invalid_address],
          "Catch-all test",
          "Plain text content!",
          "X-Spam-Status: No"
        )

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: invalid_address,
        data: data
      })

      assert is_nil(Aliases.get_email_alias_by_address(invalid_address))
      refute_email_sent(subject: "Catch-all test")

      assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.subject == "We couldn't create a catch-all alias"
        assert email.text_body =~ "The original message is attached for review."
        refute email.text_body =~ "/domains/"
        refute email.html_body =~ "/domains/"

        assert [
                 %Swoosh.Attachment{
                   filename: "original-message.eml",
                   content_type: "message/rfc822",
                   type: :attachment
                 } = attachment
               ] = email.attachments

        assert Swoosh.Attachment.get_content(attachment) == data
        true
      end)
    end

    @tag :catchall_invalid
    test "does not attach a spam message when a catch-all address is invalid", %{user: user} do
      custom_domain = custom_domain_fixture(%{user_id: user.id, catchall_enabled: true})
      invalid_address = "spam_address@#{custom_domain.domain}"

      data =
        text_email(
          "spammer@example.com",
          [invalid_address],
          "Catch-all spam test",
          "Spam content",
          "X-Spam-Status: Yes, score=5.1 required=5.0"
        )

      perform_job(EmailHandler, %{
        from: "spammer@example.com",
        to: invalid_address,
        data: data
      })

      assert is_nil(Aliases.get_email_alias_by_address(invalid_address))
      refute_email_sent(subject: "Catch-all spam test")

      assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.subject == "We couldn't create a catch-all alias"
        assert email.attachments == []

        assert email.text_body =~
                 "The original message was marked as spam, so it was not attached."

        refute email.text_body =~ "/domains/"
        refute email.html_body =~ "/domains/"
        true
      end)
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

      expected_url = ShroudWeb.Endpoint.url() <> ~p"/email-report/#{expected_report_data}"

      assert_email_sent(fn email ->
        assert email.html_body =~ expected_url
      end)
    end

    test "handles emails without a To field", %{email_alias: email_alias} do
      data = File.read!("test/support/data/no_to_field.email") |> Util.lf_to_crlf()

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data: data
      })
    end

    test "handles emails with no headers", %{email_alias: email_alias} do
      data = File.read!("test/support/data/invalid.email") |> Util.lf_to_crlf()

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
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

  describe "mailex parsing" do
    test "parses plain text emails", %{user: _user, email_alias: email_alias} do
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

    test "parses multipart emails", %{
      user: _user,
      email_alias: email_alias
    } do
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

    test "records blocked tracking domains and the forwarded count together after a successful forward",
         %{email_alias: email_alias} do
      args = tracking_pixel_email_args(email_alias)

      perform_job(EmailHandler, args)

      # Both counters are written in one transaction on successful delivery.
      assert %TrackerDomain{count: 1} =
               Repo.get_by(TrackerDomain, domain: "spy.example.com", date: Date.utc_today())

      assert Aliases.get_email_alias_by_address!(email_alias.address).forwarded == 1
    end

    test "only the first successful forward across a user's aliases includes their profile", %{
      user: user,
      email_alias: email_alias
    } do
      other_alias = alias_fixture(%{user_id: user.id})
      previous = Application.get_env(:shroud, :openpanel)
      bypass = Bypass.open()
      owner = self()

      Application.put_env(:shroud, :openpanel,
        enabled: true,
        client_id: "test-client",
        client_secret: "test-secret",
        api_url: "http://localhost:#{bypass.port}/api"
      )

      on_exit(fn ->
        for task <- Task.Supervisor.children(Shroud.Analytics.Tasks) do
          ref = Process.monitor(task)
          assert_receive {:DOWN, ^ref, :process, ^task, _reason}, 2_000
        end

        Application.put_env(:shroud, :openpanel, previous)
      end)

      Bypass.expect(bypass, "POST", "/api/track", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(owner, {:forward_event, Jason.decode!(body)["payload"]})
        Plug.Conn.resp(conn, 200, "{}")
      end)

      capture_log(fn ->
        with_failing_mailer(fn ->
          perform_job(EmailHandler, tracking_pixel_email_args(email_alias))
        end)
      end)

      refute Repo.reload!(user).has_forwarded_email

      for task <- Task.Supervisor.children(Shroud.Analytics.Tasks) do
        ref = Process.monitor(task)
        assert_receive {:DOWN, ^ref, :process, ^task, _reason}, 2_000
      end

      refute_received {:forward_event, _}

      perform_job(EmailHandler, tracking_pixel_email_args(email_alias))
      assert_receive {:forward_event, first}, 2_000
      assert first["name"] == "email_forwarded"
      assert first["profileId"] == Shroud.Analytics.profile_id(user.id)
      assert Repo.reload!(user).has_forwarded_email

      for alias <- [email_alias, other_alias] do
        perform_job(EmailHandler, tracking_pixel_email_args(alias))
        assert_receive {:forward_event, subsequent}, 2_000
        assert subsequent["name"] == "email_forwarded"
        refute Map.has_key?(subsequent, "profileId")
        assert Map.keys(subsequent["properties"]) == ["__timestamp"]
      end
    end

    test "a failed delivery does not record domains, and a retry does not inflate the count", %{
      email_alias: email_alias
    } do
      args = tracking_pixel_email_args(email_alias)

      # Attempt 1: delivery fails before we ever forward the email. Nothing should
      # be recorded, otherwise an Oban retry would inflate the counts.
      capture_log(fn ->
        with_failing_mailer(fn -> perform_job(EmailHandler, args) end)
      end)

      assert Repo.aggregate(TrackerDomain, :count) == 0
      refute_enqueued(worker: Shroud.Email.ImageFetcher)

      # Attempt 2 (the Oban retry): delivery succeeds. The domain is now counted
      # exactly once -- not twice.
      perform_job(EmailHandler, args)

      assert_enqueued(
        worker: Shroud.Email.ImageFetcher,
        args: %{url: "https://spy.example.com"}
      )

      assert %TrackerDomain{count: 1} =
               Repo.get_by(TrackerDomain, domain: "spy.example.com", date: Date.utc_today())

      assert Repo.aggregate(TrackerDomain, :count) == 1
    end
  end

  describe "postmaster delivery" do
    setup do
      original = Application.get_env(:shroud, :admin_user_email)
      Application.put_env(:shroud, :admin_user_email, "operator@example.net")

      on_exit(fn ->
        if is_nil(original),
          do: Application.delete_env(:shroud, :admin_user_email),
          else: Application.put_env(:shroud, :admin_user_email, original)
      end)
    end

    test "reserves the service address and preserves raw bytes without spam filtering", %{
      user: user
    } do
      reserved = alias_fixture(%{user_id: user.id, address: "postmaster@email.shroud.test"})
      raw = "From: reporter@example.org\r\nX-Spam-Flag: YES\r\n\r\nOriginal bytes " <> <<255>>

      assert :ok =
               perform_job(EmailHandler, %{
                 from: "reporter@example.org",
                 to: "POSTMASTER@EMAIL.SHROUD.TEST",
                 data: Base.encode64(raw)
               })

      assert_received {:email, email}
      assert email.to == [{"", "operator@example.net"}]
      assert email.from == {"Shroud postmaster", "noreply@email.shroud.test"}
      assert email.subject == "Mail to postmaster@email.shroud.test"
      assert email.html_body == nil
      assert [attachment] = email.attachments
      assert attachment.data == raw
      assert attachment.filename == "postmaster.eml"
      assert attachment.content_type == "message/rfc822"
      assert Aliases.get_email_alias!(reserved.id).forwarded == 0
      refute_received {:email, _}
    end

    test "null-sender mixed recipients retain both postmaster delivery and bounce handling" do
      Sentry.Test.setup_sentry(dedup_events: false)
      raw = "Subject: Delivery problem\r\n\r\nDetails"

      assert {:ok, _} =
               %{
                 from: "",
                 to: ["postmaster@email.shroud.test", "noreply@email.shroud.test"],
                 data: Base.encode64(raw)
               }
               |> EmailHandler.new()
               |> Oban.insert()

      assert %{success: 3, failure: 0} =
               Oban.drain_queue(queue: :outgoing_email, with_recursion: true)

      assert_received {:email, email}
      assert email.to == [{"", "operator@example.net"}]
      assert hd(email.attachments).data == raw
      refute_received {:email, _}
      assert [upload] = all_enqueued(worker: Shroud.S3.S3UploadJob)
      assert upload.args["content"] == raw
      assert [event] = Sentry.Test.pop_sentry_reports()
      assert event.fingerprint == ["shroud-unclassified-email-bounce"]
      assert event.extra == %{s3_path: upload.args["path"]}
    end

    test "custom-domain postmaster remains a customer alias", %{user: user} do
      domain = custom_domain_fixture(%{user_id: user.id})
      address = "postmaster@#{domain.domain}"
      alias_fixture(%{user_id: user.id, address: address})

      perform_job(EmailHandler, %{
        from: "reporter@example.org",
        to: address,
        data: text_email("reporter@example.org", [address], "Hello", "Customer mail")
      })

      assert_email_sent(fn email -> assert email.to == [{address, user.email}] end)
      refute_email_sent(%{to: "operator@example.net"})
    end

    test "missing or self-referencing destinations fail instead of dropping or looping" do
      args = %{from: nil, to: "postmaster@email.shroud.test", data: Base.encode64("original")}
      Application.delete_env(:shroud, :admin_user_email)
      assert {:error, :postmaster_destination_missing} = perform_job(EmailHandler, args)
      Application.put_env(:shroud, :admin_user_email, "POSTMASTER@EMAIL.SHROUD.TEST")
      assert {:error, :postmaster_forwarding_loop} = perform_job(EmailHandler, args)
      assert_no_email_sent()
    end

    test "mailer failures propagate so Oban can retry" do
      args = %{
        from: "reporter@example.org",
        to: "postmaster@email.shroud.test",
        data: Base.encode64("original")
      }

      with_failing_mailer(fn ->
        assert {:error, :simulated_smtp_failure} = perform_job(EmailHandler, args)
      end)

      assert_no_email_sent()
      assert :ok = perform_job(EmailHandler, args)
      assert_email_sent(fn email -> assert email.to == [{"", "operator@example.net"}] end)
    end
  end

  defp tracking_pixel_email_args(email_alias) do
    %{
      from: "sender@example.com",
      to: email_alias.address,
      data:
        html_email(
          "sender@example.com",
          [email_alias.address],
          "Subject",
          ~s(<html><body><p>hi</p><img src="https://spy.example.com" width="1" height="1" /></body></html>)
        )
    }
  end

  defp with_failing_mailer(fun, opts \\ []) do
    original = Application.get_env(:shroud, Shroud.Mailer)
    Application.put_env(:shroud, Shroud.Mailer, [adapter: FailingMailerAdapter] ++ opts)

    try do
      fun.()
    after
      Application.put_env(:shroud, Shroud.Mailer, original)
    end
  end
end
