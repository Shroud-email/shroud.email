# Catch-all Failure Original Email Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attach the exact original non-spam message to invalid catch-all notifications while omitting spam attachments and removing the irrelevant domain-management link.

**Architecture:** Keep notification delivery inside the existing `EmailHandler` Oban job, which already decodes and holds the raw SMTP message. `IncomingEmailHandler` decides whether the raw message is spam, passes either the bytes or `nil` to `UserNotifier`, and converts notifier delivery failures into `Swoosh.DeliveryError` so they escape recipient iteration and trigger the existing Oban retry behavior.

**Tech Stack:** Elixir 1.18+, Phoenix, Oban, Swoosh, MJML, ExUnit

## Global Constraints

- Non-spam invalid catch-all messages attach the exact raw bytes as `original-message.eml` with content type `message/rfc822`.
- Spam-marked invalid catch-all messages still send the notification but do not include an attachment.
- The notification contains no domain-management URL, button, or equivalent text.
- Do not add object storage, change SMTP size limits, redesign recipient job granularity, or solve duplicate delivery across retries.
- Preserve valid catch-all creation and uniqueness-race forwarding behavior.

---

## File Structure

- `test/shroud/email/email_handler_test.exs` — integration coverage for invalid catch-all handling, notification copy, exact attachment bytes, and spam omission.
- `lib/shroud/email/incoming_email_handler.ex` — decides whether to attach the raw message and invokes notification delivery in the current Oban job.
- `lib/shroud/accounts/user_notifier.ex` — creates the optional `message/rfc822` attachment and supplies attachment-status copy.
- `lib/shroud/email_template/catchall_alias_creation_failed.mjml` — renders attachment-status copy without the domain-management button.

### Task 1: Deliver Invalid Catch-all Notifications With an Optional Raw Message

**Files:**
- Modify: `test/shroud/email/email_handler_test.exs:954-984`
- Modify: `lib/shroud/email/incoming_email_handler.ex:1-151`
- Modify: `lib/shroud/accounts/user_notifier.ex:8-23,167-197`
- Modify: `lib/shroud/email_template/catchall_alias_creation_failed.mjml:22-43`

**Interfaces:**
- Consumes: decoded raw RFC 822 bytes passed as `data` to `IncomingEmailHandler.handle_incoming_email/3`; `SpamHandler.spam?/1`; `Swoosh.Attachment.new/2`.
- Produces: `UserNotifier.deliver_catchall_alias_creation_failed(user_id, address, original_message)` where `original_message` is raw binary data or `nil`; an email with zero or one original-message attachment.

- [ ] **Step 1: Replace the existing enqueue-only test with a failing non-spam attachment test**

In `test/shroud/email/email_handler_test.exs`, replace `"notifies the user if a catch-all address is invalid"` with:

```elixir
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
  end)
end
```

- [ ] **Step 2: Add a failing spam-without-attachment integration test**

Immediately after the non-spam test, add:

```elixir
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
  end)
end
```

- [ ] **Step 3: Run both focused tests and verify they fail for the expected reason**

Run:

```bash
mix test test/shroud/email/email_handler_test.exs --only catchall_invalid
```

Expected: both tests FAIL because the implementation only enqueues `UserNotifierJob`; no notification email or `.eml` attachment is delivered during `perform_job(EmailHandler, ...)`.

- [ ] **Step 4: Extend `UserNotifier` to support an optional attachment**

In `lib/shroud/accounts/user_notifier.ex`, change the private delivery helper to accept one optional attachment:

```elixir
defp deliver(recipient, subject, html_body, text_body, email_attachment \\ nil) do
  email =
    new()
    |> to(recipient)
    |> from({"Shroud.email", "noreply@#{Util.email_domain()}"})
    |> reply_to({"Shroud.email", "contact@shroud.email"})
    |> subject(subject)
    |> html_body(html_body)
    |> text_body(text_body)
    |> maybe_attach(email_attachment)

  with {:ok, _metadata} <- Mailer.deliver(email) do
    {:ok, email}
  end
end

defp maybe_attach(email, nil), do: email
defp maybe_attach(email, email_attachment), do: attachment(email, email_attachment)
```

Replace `deliver_catchall_alias_creation_failed/2` with:

```elixir
def deliver_catchall_alias_creation_failed(user_id, address, original_message) do
  user = Accounts.get_user!(user_id)

  {attachment_status, email_attachment} =
    case original_message do
      nil ->
        {"The original message was marked as spam, so it was not attached.", nil}

      data ->
        attachment =
          Swoosh.Attachment.new(
            {:data, data},
            filename: "original-message.eml",
            content_type: "message/rfc822"
          )

        {"The original message is attached for review.", attachment}
    end

  html_body =
    EmailTemplate.CatchallAliasCreationFailed.render(
      user_email: user.email,
      address: address,
      attachment_status: attachment_status,
      current_year: DateTime.utc_now().year
    )

  text_body = """
  ==============================

  Hi #{user.email},

  Someone sent an email to #{address} on your catch-all domain, but we couldn't
  create an alias for it because the address is invalid. Email addresses can't
  contain spaces or underscores.

  The email was not forwarded to you. If you'd like to receive emails at this
  address, please use a valid address (without underscores or spaces).

  #{attachment_status}

  ==============================
  """

  deliver(
    user.email,
    "We couldn't create a catch-all alias",
    html_body,
    text_body,
    email_attachment
  )
end
```

- [ ] **Step 5: Remove the domain link and render attachment-status copy in the MJML template**

In `lib/shroud/email_template/catchall_alias_creation_failed.mjml`, replace the paragraph/button tail after the invalid-address explanation with:

```html
<p>
  The email was not forwarded to you. If you'd like to receive emails at this
  address, please use a valid address (without underscores or spaces).
</p>

<p>{{ attachment_status }}</p>
```

Delete the `<mj-button>` for `{{ domain_url }}` entirely.

- [ ] **Step 6: Deliver directly from `IncomingEmailHandler` and omit spam attachments**

In `lib/shroud/email/incoming_email_handler.ex`, replace the `UserNotifierJob` alias with:

```elixir
alias Shroud.Accounts.UserNotifier
```

Change the invalid-address call to pass the raw message:

```elixir
notify_catchall_alias_creation_failed(recipient_user, recipient, data)
```

Replace the enqueueing helper with:

```elixir
@spec notify_catchall_alias_creation_failed(User.t(), String.t(), String.t()) :: :ok
defp notify_catchall_alias_creation_failed(%User{} = user, recipient, data) do
  original_message = if SpamHandler.spam?(data), do: nil, else: data

  case UserNotifier.deliver_catchall_alias_creation_failed(
         user.id,
         recipient,
         original_message
       ) do
    {:ok, _email} ->
      :ok

    {:error, reason} ->
      raise Swoosh.DeliveryError, reason: reason
  end
end
```

Using `Swoosh.DeliveryError` is deliberate: an exception escapes both the single-recipient and `Enum.each/2` multi-recipient paths, causing Oban to retry the current `EmailHandler` job without changing unrelated handler return semantics.

- [ ] **Step 7: Format the changed files**

Run:

```bash
mix format \
  lib/shroud/email/incoming_email_handler.ex \
  lib/shroud/accounts/user_notifier.ex \
  test/shroud/email/email_handler_test.exs
```

Expected: command exits successfully with no output.

- [ ] **Step 8: Run the focused tests and verify they pass**

Run:

```bash
mix test test/shroud/email/email_handler_test.exs --only catchall_invalid
```

Expected: both invalid catch-all tests PASS. The non-spam notice has the exact raw `.eml`; the spam notice has no attachment.

- [ ] **Step 9: Run catch-all and notifier regressions**

Run:

```bash
mix test test/shroud/email/email_handler_test.exs test/shroud/accounts/user_notifier_job_test.exs
```

Expected: all tests PASS, including valid catch-all creation, existing aliases, uniqueness handling, and existing notifier jobs.

- [ ] **Step 10: Run compile and static verification**

Run:

```bash
mix compile --warnings-as-errors
mix credo --strict
```

Expected: both commands exit successfully with no new warnings or Credo issues.

- [ ] **Step 11: Commit the implementation**

```bash
git add \
  lib/shroud/email/incoming_email_handler.ex \
  lib/shroud/accounts/user_notifier.ex \
  lib/shroud/email_template/catchall_alias_creation_failed.mjml \
  test/shroud/email/email_handler_test.exs
git commit -m "feat: attach original invalid catch-all emails"
```
