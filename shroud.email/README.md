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

## Analytics

OpenPanel is optional and production-only. Tracking is enabled when
`OPENPANEL_CLIENT_ID`, `OPENPANEL_API_URL`, and `OPENPANEL_CLIENT_SECRET` are all
nonempty. Keep the secret in the deployment's secrets. The public client ID and
API URL are shown in `example.env`. Leave the secret unset on staging.
Apply database migrations before starting the app. Subscribe the Paddle webhook
destination to `subscription.activated` as well as `subscription.created` and
the subscription update/cancellation events.
Browser screen views, outgoing links, and explicit `data-track` attributes are
enabled; session replay and error tracking are not enabled.

Authenticated browser events and backend events use a server-generated HMAC of
the account ID as `profileId`. An analytics-specific key is derived from Phoenix's
`secret_key_base`; the database ID and secret are not exposed in analytics HTML
or payloads. IDs are stable while that secret remains unchanged. Rotating it
changes analytics IDs and splits account history. No mapping table is required.
No names, email addresses, alias addresses, message content or
custom-domain names are supplied by backend analytics. Browser URL properties
replace sensitive route segments with `:token`, `:data`, `:address`, or `:domain`.
Page titles are removed. Outgoing-link text, queries, fragments and UTM
parameters remain; do not put personal data in them or tracking attributes.

Backend events are `alias_created` (with `custom_domain: true/false`),
`email_forwarded`, `outgoing_email_sent`, and `paid_conversion`. Email events mean
the mailer accepted delivery, not final recipient delivery. Conversion means the
first active Paddle subscription creation/activation or lifetime entitlement
redemption. Conversion events include `source: "paddle"` or
`source: "lifetime_code"` to distinguish the entitlement source.
Trials, checkout attempts, renewals and cancellation requests do not
emit conversions. `paid_converted_at` is persisted under an account row lock;
duplicate billing callbacks cannot repeat the conversion.

Network sends run in a bounded task supervisor, with short timeouts and no
retries. Events can be lost during outages, saturation or shutdown. Successful
email sends repeated by the mail processing pipeline produce repeated events.
OpenPanel has no durable ingestion idempotency key; these are best-effort metrics,
not a billing ledger. There is no historical backfill.

This is pseudonymous analytics, not anonymous analytics. OpenPanel receives
browser IPs and user agents and derives visitor, session, device and geographic
metadata. Backend requests do not forward customer IPs or user agents; OpenPanel
can associate them with recent browser sessions by profile ID and inherit session
metadata. Minimal backend payloads do not guarantee minimal stored data.
The SDK does not reliably merge previous anonymous visits with account history.
Marketing UTM parameters and referrers are tracked, but cross-day anonymous
marketing-to-account attribution is not guaranteed.

## Inbox aliases

The `agent_inboxes` feature flag enables inbox creation and the inbox UI. It is
off by default and supports per-user rollout through the feature-flags admin UI.
Inbox aliases store mail instead of forwarding it. Receiving mail and retention
cleanup operate independently of the UI flag. MCP and OAuth inbox access are not
exposed.

Inbox messages retain their original MIME contents and attachments, encrypted
with `Shroud.Vault` under the `inboxes/` prefix in the existing S3 bucket. The
application requires S3 PutObject, GetObject, and DeleteObject permissions. Keep
the bucket private and exclude this prefix from any automatic expiration policy
that would override the user's retention setting. Vault keys must remain available
for as long as their encrypted messages are retained.

Retention defaults to no automatic expiry. Users can set a positive number of
days per inbox or clear it to keep mail indefinitely. Retention uses receipt time
and applies to existing messages. Hourly cleanup removes expired messages,
explicitly deleted messages, and messages belonging to deleted aliases. Message
deletion immediately hides the message; its S3 object remains scheduled for
cleanup until deletion succeeds. S3 version history and backups require their own
deletion policies; deleting the current object does not erase historical copies.

Opening messages or downloading attachments does not mark them read. Read/unread
state changes only through explicit actions. The inbox UI displays message bodies
as escaped text, and attachments are authenticated downloads rather than public
S3 links. Inbox aliases cannot send mail. The existing 25 MB incoming-message
limit also applies to inbox deliveries.
