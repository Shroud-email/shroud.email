# [Shroud.email](https://shroud.email/)

[![CI](https://github.com/Shroud-email/shroud.email/actions/workflows/ci.yml/badge.svg)](https://github.com/Shroud-email/shroud.email/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/Shroud-email/shroud.email/branch/main/graph/badge.svg?token=VOCBPBLSVG)](https://codecov.io/gh/Shroud-email/shroud.email)

[Shroud.email](https://shroud.email/) is an email privacy service. Protect your email address from spammers and creepy marketers
by creating unlimited aliases that remove trackers and forward messages to your regular inbox.

This repo contains our source code. If you just want to set up your email aliases, sign up for our [free 30-day trial](https://app.shroud.email/users/register).

## Contributing

Run these commands from the monorepo's `shroud.email/` directory. Shared Git
hooks and commitlint are installed with `npm ci` at the monorepo root.

Shroud is built with Elixir and [Phoenix](https://www.phoenixframework.org/). Make sure you
have Elixir and mix installed.

Our agent guidelines live in [`AGENTS.md`](AGENTS.md). If you use Claude Code, install
something like the [agents-md-loader](https://tangled.org/btao.org/claude-agents-md-loader)
so that Claude Code reads `AGENTS.md` files (it does not pick them up natively).

To start the server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Create seed data (if you want) using `mix ecto.seed`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Passkeys use the configured Phoenix endpoint URL as their WebAuthn origin and RP ID.
Set `APP_DOMAIN` to the canonical public HTTPS host in production, or the public
portal host when developing through an HTTPS portal. Serve login and Security
settings on that same host. Without `APP_DOMAIN`, development uses plain HTTP on
`localhost`; passkeys enrolled on one host cannot be used on another. Apply
database migrations before enabling passkey enrollment.

Mobile and extension clients use OAuth Authorization Code with PKCE.
Official client IDs, exact callbacks, and security settings are stored in the
database. Run `mix ecto.migrate` to provision the mobile and ChatGPT clients.
For the published ChatGPT plugin, configure predefined public client ID
`7b705cee-124c-4abe-827f-d61c030c32c0`. Its callback is
`https://chatgpt.com/connector_platform_oauth_redirect`, documented for servers
with issuer identification in [OpenAI's auth guide](https://developers.openai.com/plugins/build/auth).

To send test emails, use e.g. [Swaks](https://www.jetmore.org/john/code/swaks/):
```
swaks --to test@example.com --server 127.0.0.1 --port 2525
```

## Libraries

- [Tailwind CSS](https://tailwindcss.com/) for styles
- [gen_smtp](https://github.com/gen-smtp/gen_smtp) for receiving emails
- [Swoosh](https://hexdocs.pm/swoosh/Swoosh.html) for sending emails

# Deploying

Set the environment variables in `example.env`.

Relayed emails carry an authenticated, encrypted `X-Shroud-Delivery` header.
It identifies the alias owner, delivery direction, and recipient without a
delivery timestamp or database correlation record. Keep `SECRET_KEY_BASE` stable
across instances; changing it invalidates markers in outstanding messages.
Haraka returns original headers in its delivery-status reports. Reports that omit
the marker, contain a modified marker, or do not match its alias and recipient
cannot trigger user notifications.

Authenticated outgoing terminal failures produce a plain-text notification to
the alias owner's current account email. Delays and successful deliveries do not
produce notifications. The original subject is included only when it matches the
authenticated subject hash. Reasons use delivery-status codes, not untrusted
report text. Notifications carry no delivery marker, preventing notification loops.
Notifications use the transactional email queue with up to ten delivery attempts.
Duplicate reports are suppressed
using opaque hashes in a single-node, in-memory 15-minute fixed window. The
window resets on restart and at aligned boundaries; there is no persistent or
cross-instance exactly-once guarantee.

With `SENTRY_DSN` configured, warning-level bounce events use these fingerprints:

- `shroud-unclassified-email-bounce`: unmatched or malformed reports.
- `shroud-incoming-forwarding-bounce`: incoming mail could not reach a user's inbox.
- `shroud-outgoing-delivery-rejection`: outgoing routing or policy failures.

Ordinary outgoing address or mailbox rejections notify the user without creating
a Sentry issue. Inbox-forwarding failures alert operators rather than sending
more email to the rejecting inbox. There is no persistent delivery-warning UI.
Raw bounce reports are archived to S3. Each Sentry event's `extra.s3_path`
identifies its object in the configured email bucket. The path includes the alias
and timestamp; Sentry receives no raw message content or inherited user context.
Classified alerts also include a validated delivery-status code. Uploads run
asynchronously, so the object may not be available immediately when alerted. The SDK
deduplicates identical events within approximately 30 seconds, so the issue's
event count is not an exact bounce count.

Configure Sentry issue alerts for these bounce events, including warning-level
events and both new and recurring occurrences. Set a notification interval to
limit noise. Grouping alone does not enable notifications.

The SMTP processing queue stores envelope addresses and message bodies in Oban
job arguments. Bounce notification jobs store the user ID, alias, recipient,
verified subject, reason, and status. Bounce handling adds no delivery-history
or correlation records.
