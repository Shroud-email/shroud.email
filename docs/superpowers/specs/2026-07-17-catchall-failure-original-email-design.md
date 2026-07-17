# Catch-all Alias Failure Original Email Design

## Goal

When an incoming message targets an invalid address on a catch-all domain, notify the domain owner and let them recover legitimate mail without forwarding content that SpamAssassin marked as spam.

## Behavior

- Alias creation still fails for addresses rejected by `EmailAlias.changeset/2`, such as local parts containing spaces or underscores.
- The incoming message is not forwarded and no alias is created.
- The system sends the domain owner the existing “We couldn't create a catch-all alias” notification.
- If `SpamHandler.spam?/1` returns `false`, the notification includes the exact raw incoming message as an attachment:
  - filename: `original-message.eml`
  - content type: `message/rfc822`
- If `SpamHandler.spam?/1` returns `true`, the notification has no attachment and explains that the original was omitted because it was marked as spam.
- The notification contains no “Manage domain” button, URL, or equivalent text. The domain page does not help recover an invalid incoming address.

## Architecture and Data Flow

The existing `EmailHandler` Oban job already contains the Base64-encoded SMTP message. It decodes that value before calling `IncomingEmailHandler`, so attachment delivery should use the decoded raw message directly rather than copying it into a second Oban job.

The invalid catch-all flow is:

1. `EmailHandler` decodes the raw SMTP message.
2. `IncomingEmailHandler` attempts catch-all alias creation.
3. Alias validation fails with a non-uniqueness changeset error.
4. `IncomingEmailHandler` calls `SpamHandler.spam?/1` on the raw message.
5. `UserNotifier` builds and delivers the notification synchronously within the current `EmailHandler` job.
6. For non-spam, `UserNotifier` adds a `Swoosh.Attachment` created from `{:data, raw_message}`. For spam, it adds no attachment.

The existing uniqueness-race handling remains unchanged: a uniqueness constraint error forwards the message through the alias that another concurrent job created.

## Delivery Failure Handling

If notification delivery returns `{:error, reason}`, the invalid catch-all path propagates that error through `EmailHandler.perform/1`. Oban marks the existing job retryable and retries it according to `EmailHandler`'s current worker configuration. Other incoming-email branches retain their current return behavior.

This design does not attempt to solve recipient-level idempotency for jobs containing multiple SMTP envelope recipients. Duplicate processing after a later-recipient failure is a pre-existing job-granularity concern and is outside this change.

## Notification Copy

The HTML and text bodies retain the explanation that the requested alias address was invalid.

They add one status-specific sentence:

- Non-spam: “The original message is attached for review.”
- Spam: “The original message was marked as spam, so it was not attached.”

The domain-management link and button are removed from both variants.

## Testing

Tests will verify:

1. A non-spam message sent to an invalid catch-all address creates no alias and is not forwarded.
2. The resulting notification has the expected recipient and subject.
3. The notification has one `message/rfc822` attachment named `original-message.eml` whose bytes exactly equal the raw incoming message.
4. A spam-marked invalid catch-all message still sends the notification but has no attachment.
5. The HTML and text notification bodies contain the correct attachment-status copy and no domain-management link.
6. Existing valid catch-all creation and uniqueness-race behavior remain unchanged.

## Out of Scope

- Storing raw messages in S3 or another temporary object store.
- Changing SMTP message-size limits.
- Redesigning `EmailHandler` into one job per SMTP recipient.
- Solving duplicate delivery across Oban retries.
- Changing SpamAssassin thresholds or header trust.
