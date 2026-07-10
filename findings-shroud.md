# Findings: shroud.email inbound email processing & Haraka responsibilities

Read-only investigation of `/Users/tao/dev/shroud/shroud.email` (main checkout), cross-referenced with the `hosting` repo's `docker-compose.yaml` only to confirm network topology. No files modified.

## 1. SMTP listener: library, port, TLS

### Library
shroud runs its own SMTP listener via **`gen_smtp`** (`{:gen_smtp, "~> 1.3"}` in `mix.exs`), implementing the `:gen_smtp_server_session` behaviour.

- `lib/shroud/email/smtp_server.ex:3` — `@behaviour :gen_smtp_server_session`
- `lib/shroud/email/smtp_server.ex:20` — `:gen_smtp_server.start(__MODULE__, options)`
- Started under the app supervisor in `lib/shroud/application.ex:30`:
  ```elixir
  {Shroud.Email.SmtpServer, Application.fetch_env!(:shroud, :mailer)[:smtp_options]}
  ```

### Port
The inbound SMTP port is **1587** (NOT 2525 — the AGENTS.md note is stale).

- `config/config.exs:33-34` (dev/default): `smtp_options: [port: 1587, ...]`
- `config/prod.exs:18-19` (prod): `smtp_options: [port: 1587, ...]`
- `config/test.exs:33-34`: `smtp_options: [port: 2526]`
- Confirmed by the hosting `docker-compose.yaml` which publishes `"1587:1587"` for the `web` (shroud) container.

### TLS termination on inbound
shroud's gen_smtp server **advertises STARTTLS and is capable of its own TLS termination**, but the config suggests it is normally reached over a private network from Haraka, not the public internet.

- `lib/shroud/email/smtp_server.ex:36-38` — EHLO advertises STARTTLS:
  ```elixir
  extensions = extensions ++ [{to_charlist("STARTTLS"), true}]
  ```
- `lib/shroud/email/smtp_server.ex:85-86` — `handle_STARTTLS(state)` returns state unchanged (the actual TLS upgrade is done by gen_smtp's session module using `tls_options`).
- `deps/gen_smtp/src/gen_smtp_server_session.erl:863-900` — gen_smtp performs the `ranch_ssl:handshake` using `proplists:get_value(tls_options, Options, [])` when STARTTLS is received. So with `tls_options` set, shroud CAN terminate TLS itself.
- `config/prod.exs:21-26` / `config/config.exs:36-41`:
  ```elixir
  tls_options: [
    verify: :verify_none,
    log_level: :info
  ]
  ```
  Note: no `certfile`/`keyfile` is configured anywhere in shroud's own config — the `tls_options` only set peer verification. gen_smtp would still need a cert/key to complete a real handshake; in production the cert lives in the hosting layer (`haraka_config/config/certs` volume, per `docker-compose.yaml`). So in practice TLS termination today is Haraka's job on the public port (25/465); shroud's STARTTLS path is wired but the cert is not provisioned inside the shroud container.

## 2. Inbound processing pipeline

Flow (per email, enqueued as an Oban job):

1. **SMTP receive** — `SmtpServer.handle_DATA/4` (`smtp_server.ex:43-56`) base64-encodes the raw RFC822 data and inserts an `EmailHandler` Oban job on the `:outgoing_email` queue (yes, the queue name is misleading — it carries both directions).
   - `handle_RCPT/2` (`smtp_server.ex:30-32`) returns `{:ok, state}` **unconditionally** — shroud accepts ALL recipients at the SMTP layer and validates later. There is no SMTP-level recipient rejection.
2. **Oban dispatch** — `EmailHandler.perform/1` (`email_handler.ex:18-29`) decodes data and routes:
   - `from in ["", nil]` → `BounceHandler.handle_haraka_bounce_report/2` (Haraka bounce report).
   - size > 25 MB (`email_handler.ex:32-44`) → silently dropped.
   - `ReplyAddress.reply_address?(recipient)` → `OutgoingEmailHandler` (user reply).
   - otherwise → `IncomingEmailHandler` (alias forward).
3. **Incoming** — `IncomingEmailHandler.handle_incoming_email/3` (`incoming_email_handler.ex:21-92`):
   - Looks up `Accounts.get_user_by_alias(recipient)` and the `EmailAlias`. **Recipient validation against the DB happens here, post-acceptance** — unknown recipients are logged and discarded (line 47-50), not rejected at SMTP.
   - Catch-all custom domains → creates an alias on the fly (`create_catchall_address/4`).
   - Disabled alias → discarded, `increment_blocked!`.
   - Sender in `blocked_addresses` → discarded, `increment_blocked!`.
   - `SpamHandler.spam?(data)` → `SpamHandler.handle_incoming_spam_email/4` (stored to `spam_emails` table, user notified), `increment_blocked!`.
   - Otherwise → `forward_incoming_email/4`:
     - `ParsedEmail.parse(Mailex.parse!(data), sender, recipient)` → `TrackerRemover.process()` → `Enricher.process()` → rewrite From/To/Reply-To via `ReplyAddress` → `Mailer.deliver()` (Swoosh).
4. **ParsedEmail** — `lib/shroud/email/parsed_email.ex` converts a `:mimemail.mimetuple()` or `Mailex.Message.t()` into a `Swoosh.Email`, only carrying allow-listed headers (`from, subject, to, reply-to, date, delivered-to`, `parsed_email.ex:18-23`).
5. **Tracker removal** — `lib/shroud/email/tracker_remover.ex` strips known tracker pixels/1x1 images via Floki against `Email.list_trackers()`, replacing image URLs with proxied ones.
6. **Enricher** — `lib/shroud/email/enricher.ex` appends the "Forwarded by Shroud.email / removed N trackers" footer to text and HTML bodies.
7. **Forwarding** — via `Shroud.Mailer` (Swoosh). See §7.

## 3. SpamAssassin integration — shroud does NOT call spamd

**shroud never talks to SpamAssassin.** It only *reads* the `X-Spam-Status` header that an upstream MTA (Haraka) injects.

There is no `spamd`/`spamc` client anywhere in `lib/` or `config/`:
- `grep -rn "spamd\|spamc\|:spamassassin" lib/ config/` → only the `spamassassin_header` field name in the schema (`spam_email.ex:12,28`).

The entirety of shroud's spam detection (`lib/shroud/email/spam_handler.ex:25-32`):
```elixir
@spec spam?(String.t()) :: boolean()
def spam?(data) do
  data
  |> Mailex.parse!()
  |> get_spamassassin_header()
  |> String.downcase()
  |> String.trim_leading()
  |> String.starts_with?("yes, ")
end
```

`get_spamassassin_header/1` (`spam_handler.ex:95-137`) reads the `x-spam-status` header from either a `Mailex.Message` struct or a `:mimemail.mimetuple()`:
```elixir
def get_spamassassin_header(%Mailex.Message{headers: headers}) do
  case Map.get(headers, "x-spam-status", "") do
    "" ->
      sender = Map.get(headers, "from", "")
      recipient = Map.get(headers, "to", "")
      Logger.warning(
        "Received an email from #{sender} to #{recipient} without a SpamAssassin header"
      )
      ""
    value when is_binary(value) -> value
    [value | _] -> value
  end
end
```
- If the header is missing, shroud logs a warning and treats the email as **not spam** (empty string does not start with `"yes, "`). This is a silent fail-open.
- The docstring (`spam_handler.ex:18-24`) explicitly states: *"configuration of spam detection thresholds etc. is done in SpamAssassin, not here."*

### Where the header comes from
Confirmed by `hosting/docker-compose.yaml`: a separate `dinkel/spamassassin` container runs, and the `haraka` container `depends_on: [spamassassin, db]`. Haraka's spamassassin plugin talks to `spamd` and adds `X-Spam-Status` (and related) headers before forwarding the message to shroud on port 1587. **shroud's spam pipeline is entirely dependent on Haraka running SpamAssassin and injecting headers.**

### Storage of spam
- `lib/shroud/email/spam_email.ex` — `spam_emails` table: `from, subject, html_body, text_body, spamassassin_header, user_id, email_alias_id`.
- Migration `priv/repo/migrations/20220706084353_create_spam_emails.exs` (original table) and `20250323125922_add_spamassassin_header_to_spam_emails.exs` (added the `spamassassin_header` text column).
- `Shroud.Email.store_spam_email!/3` (`lib/shroud/email.ex:57-79`) sanitizes HTML via `Shroud.Email.SpamEmailScrubber` and inserts.
- `Shroud.Email.delete_old_spam_emails/0` (`email.ex:112-118`) deletes rows older than 7 days; called by the Quantum scheduler (see §6).
- "Detention" LiveView: `lib/shroud_web/live/spam_email_live/index.{ex,html.heex}`, route `live("/detention", SpamEmailLive.Index, :index)` (`router.ex:131`).

## 4. config/runtime.exs and env vars

`config/runtime.exs` (prod block) configures **outbound** Swoosh only:
```elixir
config :shroud, Shroud.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: smtp_relay,            # default "localhost"; hosting sets SMTP_RELAY=haraka
  username: smtp_username,
  password: smtp_password,
  ssl: false,
  tls: :always,
  auth: :always,
  port: 25,
  retries: 5,
  no_mx_lookups: true,
  tls_options: [verify: :verify_none]
```
- `SMTP_USERNAME` / `SMTP_PASSWORD` are **required** (`raise` if missing) — these are the credentials shroud uses to authenticate to Haraka for outbound relay on port 25.
- `SMTP_RELAY` defaults to `"localhost"`; hosting sets it to `haraka`.
- No env var for the *inbound* port (hardcoded to 1587 in config files). No env var for spam, haraka, or TLS cert paths in shroud's own config.

Other relevant env: `EMAIL_DOMAIN`, `APP_DOMAIN`, `NOTIFIER_WEBHOOK_URL`, `ADMIN_EMAIL`, `S3_BUCKET`/`S3_HOST` (bounce upload), `SENTRY_DSN`.

## 5. Migrations / schemas for spam, quarantine, detention

- `priv/repo/migrations/20220706084353_create_spam_emails.exs` — `spam_emails` table (from, subject, html_body, text_body, user_id, email_alias_id).
- `priv/repo/migrations/20250323125922_add_spamassassin_header_to_spam_emails.exs` — adds `spamassassin_header :text`.
- `lib/shroud/email/spam_email.ex` — schema.
- No separate "quarantine" table; detention is just the user-facing view over `spam_emails`.
- No migration references Haraka directly; the only Haraka-coupled code is `BounceHandler.handle_haraka_bounce_report/2`.

## 6. Oban queues & Quantum jobs

### Oban queues (`config/config.exs:80-86`)
```elixir
queues: [default: 1, outgoing_email: 5, notifier: 1, dns_checker: 3]
```
Note: the `:outgoing_email` queue (concurrency 5) handles **both** inbound and outbound email via `Shroud.Email.EmailHandler` (the worker's `use Oban.Worker, queue: :outgoing_email, max_attempts: 100` at `email_handler.ex:2`). The name is a historical misnomer.

### Quantum scheduled jobs (`config/config.exs:50-54`, `lib/shroud/scheduler.ex`)
```elixir
{"@daily",   {Shroud.Scheduler, :update_trackers, []}},      # tracker list refresh
{"@hourly",  {Shroud.Scheduler, :delete_spam_emails, []}},   # spam cleanup (>7 days)
{"@hourly",  {Shroud.Scheduler, :verify_custom_domains, []}} # DNS verification
```
`delete_spam_emails/0` (`scheduler.ex`) → `Email.delete_old_spam_emails/0` (`email.ex:112-118`): `DELETE FROM spam_emails WHERE inserted_at < now() - interval '7 days'`.

## 7. Outbound mail — goes through Haraka, not direct to a provider

`Shroud.Mailer` (`lib/shroud/mailer.ex`) is `use Swoosh.Mailer, otp_app: :shroud`. In prod (`config/runtime.exs`) it uses `Swoosh.Adapters.SMTP` pointed at `SMTP_RELAY` (=`haraka`) on **port 25** with `tls: :always` and `auth: :always`. So **all outbound mail (forwarded inbound, plus user replies) is relayed through Haraka**, which presumably does DKIM signing / outbound queueing / blocklist handling. shroud has **no DKIM signing code** of its own.

- `OutgoingEmailHandler.forward_outgoing_email/4` (`outgoing_email_handler.ex:39-66`) → `Mailer.deliver()`.
- `IncomingEmailHandler.forward_incoming_email/4` (`incoming_email_handler.ex:99-138`) → `Mailer.deliver()`.
- Bounce reports from Haraka come back *into* shroud's SMTP server as messages with empty `from` (`email_handler.ex:24-25`), handled by `BounceHandler.handle_haraka_bounce_report/2` (`bounce_handler.ex:17-26`) which uploads the .eml to S3 and logs a warning. The docstring (`bounce_handler.ex:9-15`) explicitly says these come from Haraka when outbound delivery fails (e.g. 554 because the MTA IP is on a blocklist).

## 8. Haraka responsibilities shroud has NO code for

If Haraka is removed, the following must be absorbed by shroud (or another layer). shroud currently has **zero** code for each:

| Responsibility | shroud has it? | Evidence |
|---|---|---|
| Public SMTP listener on port 25 / 465 (with real TLS cert) | **No** — shroud binds 1587 with no cert configured | `config/prod.exs:18-26`; hosting `docker-compose.yaml` maps 25 & 465 → haraka |
| TLS termination on inbound (real cert, not verify-none) | **Partial** — gen_smtp can do STARTTLS but no cert/keyfile is configured in shroud; cert lives in hosting `haraka_config/config/certs` | `smtp_server.ex:36-38,85`; `config/prod.exs:21-26` |
| SpamAssassin (`spamd`) integration — actually running SA and injecting `X-Spam-Status` | **No** — shroud only *reads* the header | `spam_handler.ex:25-32`; `hosting/docker-compose.yaml` `spamassassin` + `haraka depends_on spamassassin` |
| DKIM signing of outbound mail | **No** — shroud has only *inbound DNS verification* of custom-domain DKIM/SPF/DMARC records (`lib/shroud/domain/dns_record.ex:50-71`, `dns_checker.ex:30-50`), no signing | — |
| ARC (Authenticated Received Chain) | **No** | grep finds nothing |
| Greylisting | **No** | grep finds nothing |
| RBL / DNSBL lookups | **No** | grep finds nothing |
| Rate limiting / connection throttling | **No** — `handle_RCPT`, `handle_MAIL` accept everything unconditionally | `smtp_server.ex:24-34` |
| Recipient validation at SMTP time (reject unknown recipients before DATA) | **No** — `handle_RCPT` always returns `{:ok, state}`; validation happens post-DATA in `IncomingEmailHandler` and silently discards | `smtp_server.ex:30-32`; `incoming_email_handler.ex:47-50` |
| Outbound relay auth / blocklist management / 551/554 retry handling | **No** — shroud relies on Haraka as the smarthost; bounces come back as inbound messages | `bounce_handler.ex:9-26`; `config/runtime.exs` Mailer → `haraka:25` |
| SMTP AUTH (inbound) | Wired but permissive — `handle_AUTH/3` (`smtp_server.ex:80-83`) always returns `{:ok, state}` (accepts any credentials) | — |

## 9. Start here

`lib/shroud/email/smtp_server.ex` — the entire inbound SMTP surface (40 lines of real logic). It shows that shroud's listener is a thin accept-everything shim that hands raw bytes to Oban. Combined with `lib/shroud/email/spam_handler.ex` (header-only spam detection) and `lib/shroud/email/email_handler.ex` (Oban dispatch + Haraka bounce routing), this is the surface area that would have to grow to absorb Haraka.

## Key risks / open questions

- **SpamAssassin is the biggest gap.** shroud's spam detection fail-opens if the `X-Spam-Status` header is absent (`spam_handler.ex:103-110`). Removing Haraka without replacing SA + header injection means *all* spam classification silently stops. Either shroud must call `spamd` itself (new code), or another MTA layer must inject the header.
- **Recipient validation moves from silent discard to SMTP-time rejection** if Haraka goes away — currently unknown recipients are accepted then dropped (`incoming_email_handler.ex:47-50`), which is fine when Haraka does the SMTP-level rejection first. Without Haraka, shroud would become a backscatter source unless `handle_RCPT` is taught to query the alias DB.
- **Outbound delivery** currently depends on Haraka as smarthost (`SMTP_RELAY=haraka`, port 25). Removing Haraka requires pointing Swoosh at a real provider (or running an outbound MTA) and adding DKIM signing, neither of which shroud has.
- **TLS cert provisioning**: shroud's `tls_options` lack `certfile`/`keyfile`; the cert is managed in the hosting/Haraka layer. A direct-internet shroud listener would need its own cert lifecycle.
- The `:outgoing_email` Oban queue name is misleading (handles both directions) — cosmetic, but worth noting for anyone refactoring.
