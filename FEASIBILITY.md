# Feasibility: Removing Haraka and linking shroud.email directly to SpamAssassin

**Branch:** `explore/haraka-removal` (worktree `.worktrees/explore-haraka-removal`)
**Date:** 2026-07-04
**Verdict:** Technically feasible, but Haraka is **not** a thin forwarder. Removing it means re-homing ~9 distinct responsibilities into shroud (or a successor). The SpamAssassin piece is the easiest part; outbound delivery + DKIM + TLS cert lifecycle are the hardest. See the recommendation at the bottom.

This document draws on three parallel investigations whose full reports sit
alongside it: `findings-hosting.md`, `findings-shroud.md`, `findings-history.md`.

---

## 1. What Haraka is and why it's there

### The one-line answer
Haraka is shroud.email's **public-facing MTA**. It owns the internet-facing SMTP
surface (ports 25 and 465) and a chunk of mail policy that the Elixir app never
implemented. shroud.email itself only listens on the private `:1587` and accepts
everything Haraka hands it.

### How the mail flows today
```
Internet  ──:25 (STARTTLS) / :465 (implicit TLS)──►  Haraka
                                                       │  dnsbl, backscatterer, helo.checks,
                                                       │  tls, auth/env_var, mail_from.is_resolvable,
                                                       │  spf, rcpt_to.in_host_list_shroud (PG query),
                                                       │  headers, spamassassin ──► spamd spamassassin:783,
                                                       │  dkim_sign, bounce_logger,
                                                       │  queue/smtp_forward
                                                       │
                                                       ▼  plain SMTP, host=web port=1587, enable_tls=false
                                              shroud web (gen_smtp, :1587)
                                                       │  reads X-Spam-Status header,
                                                       │  tracker removal, spam detention,
                                                       │  forward via Swoosh SMTP
                                                       ▼  SMTP_RELAY=haraka, port 25, TLS+auth
                                              Haraka (outbound queue) ──► internet MX
```
Source: `hosting/docker-compose.yaml`, `hosting/haraka/haraka_config/config/plugins`,
`config/smtp_forward.ini`, `config/spamassassin.ini`.

### Everything Haraka does (the full responsibility list)
| # | Responsibility | shroud has code for it? |
|---|---|---|
| 1 | Public SMTP listener on **25** and **465** | No — shroud binds `:1587` only |
| 2 | TLS termination with a real Let's Encrypt cert (minted by Caddy, copied in by the `cron` sidecar via the `pem_certs` volume) | Partial — gen_smtp can do STARTTLS but no `certfile`/`keyfile` is configured in shroud |
| 3 | SMTP AUTH (CRAM-MD5/PLAIN/LOGIN) against `SMTP_USERNAME`/`SMTP_PASSWORD` | Wired but permissive — `handle_AUTH/3` accepts any credentials |
| 4 | DNSBL + backscatterer IP blocklisting on connect | No |
| 5 | HELO checks, SPF, MAIL FROM MX-resolvable, header limits | No |
| 6 | **Recipient validation against Postgres** (`SELECT domain FROM custom_domains` ∪ `EMAIL_DOMAIN`) at SMTP time, plus anti-spoof on MAIL FROM | No — shroud's `handle_RCPT` always returns `{:ok, state}`; unknown recipients are accepted at SMTP and silently discarded post-DATA in `IncomingEmailHandler` |
| 7 | **SpamAssassin scanning** via spamd over TCP to `spamassassin:783`; rejects score ≥ 6; injects `X-Spam-Status` | No — shroud only *reads* the header |
| 8 | **DKIM signing of outbound** (selector `shroudemail`, per-domain keys under `config/dkim/<domain>/`) | No — shroud only verifies *inbound* custom-domain DKIM/SPF/DMARC records, never signs |
| 9 | **Outbound MX delivery** via Haraka's `outbound` queue (`always_split=true`) | No — shroud relays all outbound (forwarded inbound + user replies) to `SMTP_RELAY=haraka:25` via Swoosh |
| 10 | Bounce logging (custom `bounce_logger.js`) | Partial — shroud *handles* Haraka bounce reports (`BounceHandler.handle_haraka_bounce_report/2`, uploads .eml to S3) but does not generate them |

Source: `findings-hosting.md` §"Every enabled plugin"; `findings-shroud.md` §8.

### Why Haraka was introduced (git history)
- Both repos are by Tao Bojlén. The hosting repo's reflog shows Haraka and
  SpamAssassin were added **the same day, 2022-06-26**, two days after the
  project's initial commit. The first Haraka commit is literally titled
  *"use haraka for outgoing emails"* — Haraka entered as an **outbound relay**
  and grew into the inbound MTA role afterward.
- Branch names in the shroud.email repo (`use-postfix`, `use-haraka`,
  `remove-oh-my-smtp`, tag `own-relay`) show the MTA was chosen deliberately:
  external relay → "oh-my-smtp" → Postfix → Haraka, all in mid-2022.
- The 2022-07-19 commit *"read custom domains in haraka"* promoted Haraka from
  relay to first-class infra by giving it direct Postgres access for recipient
  validation.
- **No ADR, ARCHITECTURE.md, or design doc exists in either repo.** The commit
  messages are one-liners with no rationale. So there is no recorded *reason*
  for Haraka beyond "we needed an MTA and picked this one" — which means there
  is no institutional commitment to it, but also no documented analysis to
  lean on.
- SpamAssassin has **always** been Haraka's job. shroud.email has never talked
  to spamd. The `spam_handler.ex` docstring says so outright: *"configuration
  of spam detection thresholds etc. is done in SpamAssassin, not here."*

---

## 2. Can we remove Haraka entirely?

### The direct answer
**Yes, but "remove Haraka" is a much bigger task than "call SpamAssassin from Elixir."**
Haraka is doing nine jobs, of which SpamAssassin is one. To drop it you must
re-home every row in the table above, or accept losing that capability.

### What the SpamAssassin piece specifically requires
This is the part you asked about, and it is the most tractable:

1. **Keep the `dinkel/spamassassin` container.** It already exposes spamd on
   `:783`. Nothing about Haraka's removal forces you to run SA in-process.
2. **Add a tiny spamd client to shroud.** The spamd protocol is a ~50-line TCP
   text exchange (`PROCESS SPAMC/1.5` → `SPAMD/1.1 0 EX_OK` + headers). A
   `GenServer` that opens a `:gen_tcp` connection to `spamassassin:783`, sends
   the raw RFC822 body, and parses the returned headers is straightforward.
   Alternatively, shell out to `spamc` (the CLI ships with SpamAssassin) — one
   `System.cmd("spamc", ...)` call, zero protocol code. **The CLI is the lazy
   option.**
3. **Reuse the existing header-parsing logic.** `SpamHandler.get_spamassassin_header/1`
   already knows how to read `X-Spam-Status`. If you call spamd yourself, you
   inject that header into the parsed message before the existing
   `SpamHandler.spam?/1` check; the downstream `spam_emails` detention flow is
   untouched.
4. **Decide where in the pipeline to scan.** Today SA runs in Haraka *before*
   the message reaches shroud, so SA's reject (score ≥ 6) drops the connection
   at SMTP time and shroud never sees it. If you move SA into shroud, the
   message has already been accepted at SMTP `RCPT`/`DATA` — so a "reject"
   becomes either (a) a silent discard in `IncomingEmailHandler` (what already
   happens for spam today, just at a different threshold), or (b) a
   post-DATA SMTP 5xx if you make the gen_smtp server synchronous. Option (a)
   is the smaller diff and matches existing behaviour; option (b) avoids
   backscatter but requires changing `handle_DATA` to block on the scan.

### What the *rest* of Haraka removal requires (the actual cost)
This is where the work is. Ranked by effort/risk:

- **Outbound delivery + DKIM signing (hardest).** Today shroud sends all
  outbound mail to `haraka:25` via Swoosh, and Haraka signs (DKIM, selector
  `shroudemail`) and delivers to MX. Remove Haraka and you need either:
  - A replacement SMTP smarthost (e.g. an external transactional provider —
    SES, Postmark, MXRoute), configured as `SMTP_RELAY`; or
  - Direct MX delivery from Elixir (Swoosh supports it, but you lose queueing,
    retry, and blocklist handling that Haraka gave you for free) **plus** a
    DKIM signer (Erlang/Elixir has no batteries-included DKIM signer; you'd
    reach for `:public_key` + a small signing module, or add a dep).
  Bounce handling also changes shape — currently `BounceHandler` parses Haraka's
  bounce report format; a new relay produces different bounce formats.
- **TLS cert lifecycle on 25/465.** Haraka terminates TLS using Caddy-issued
  certs that the `cron` sidecar bundles into the `pem_certs` volume. If shroud
  listens on 25/465 directly, it needs the cert/keyfile in its own
  `tls_options` (`certfile`/`keyfile`), and the cron cert-bundling job either
  stays (now copying into a volume the shroud container mounts) or is replaced
  by shroud doing ACME itself (bigger lift; libraries like `site_encrypt`
  exist but it's net-new infra).
- **SMTP-time recipient validation.** Haraka's `rcpt_to.in_host_list_shroud`
  rejects unknown recipients *before* DATA. shroud currently accepts everyone
  at `RCPT` and silently drops unknowns in `IncomingEmailHandler`
  (`incoming_email_handler.ex:47-50`). Without Haraka, shroud becomes a
  backscatter source unless `handle_RCPT` learns to query the aliases /
  custom_domains tables. The query already exists in app code
  (`Accounts.get_user_by_alias/1`); wiring it into `handle_RCPT` is small but
  requires a DB call per RCPT — cache or accept the latency.
- **Auth, DNSBL, SPF, HELO, anti-spoof.** Each is a discrete piece of policy
  Haraka enforces. shroud's `handle_AUTH` is a no-op that accepts everything;
  there is no DNSBL/SPF/HELO code at all. These are *optional* for an alias
  service but Haraka provides them; dropping them is a posture decision, not
  just an engineering one. gen_smtp doesn't ship them.
- **Port 25 vs 2526 vs 1587.** Binding 25 inside a container needs either
  root or `CAP_NET_BIND_SERVICE`; the current `:1587` choice sidesteps that.
  Direct internet-facing 25 also attracts far more abuse traffic than the
  private `:1587` does, which raises the stakes on items 4 and 5 above.

### What you *keep* losing even with a perfect port
- Haraka's `outbound` queue retries and `always_split` per-recipient delivery
  semantics. Oban gives you retries for inbound, but outbound retry/backoff
  today is Haraka's. Swoosh has `retries: 5` but no persistent queue.
- The committed-example DKIM private key at
  `hosting/haraka/haraka_config/config/dkim/example.com/private` is a separate
  hygiene issue worth fixing regardless of this decision.

---

## 3. Recommendation

**Don't frame this as "remove Haraka." Frame it as "which Haraka jobs do we want to own."**

The lazy, high-value path is a **partial** move, not a full removal:

1. **Move SpamAssassin into shroud now** (call `spamc` from Elixir, inject the
   `X-Spam-Status` header, leave the rest of the pipeline alone). This is a
   ~1-day change, de-risks the SA container's lifecycle from Haraka's, and
   lets you delete the `haraka` spamassassin plugin config. It does *not*
   require touching ports, TLS, or outbound.
2. **Leave Haraka as the internet-facing MTA** until you have a separate
   decision about outbound delivery and DKIM. Those are the expensive parts
   and they are orthogonal to the SpamAssassin question.

If the actual goal is "stop running a Node.js MTA we don't deeply understand,"
then the full removal is the right *target* but it's a multi-week project, not
a refactor, and the sequencing is: outbound relay decision → DKIM strategy →
TLS cert strategy → SMTP-time recipient validation → SA-in-shroud → cut
over. SA-in-shroud is the *last* easy win on that list, not the first step.

### Open questions for you
1. Is the motivation **operational simplicity** (fewer moving parts) or
   **cost** (one fewer container/image to build) or **capability** (want SA
   rules shroud can tune per-user)? The answer changes which slice is worth
   doing first.
2. Are you willing to use an external transactional provider for outbound
   (SES/Postmark)? If yes, the outbound+DKIM problem collapses to a config
   change and full Haraka removal becomes realistic. If no (you want to keep
   self-hosting delivery), Haraka is doing hard work you'd have to re-build.
3. Port 25 directly on the shroud container — acceptable, or do you want a
   TLS-terminating proxy (Caddy/HAProxy) in front either way? The latter keeps
   the cert lifecycle out of the Elixir app.

---

## 4. Source evidence index

- **Haraka config (authoritative plugin list + order):** `hosting/haraka/haraka_config/config/plugins`
- **Forwarding to shroud:** `hosting/haraka/haraka_config/config/smtp_forward.ini` → `host=web port=1587 enable_tls=false`
- **SpamAssassin wiring:** `hosting/haraka/haraka_config/config/spamassassin.ini` → `spamd_socket = spamassassin:783`, `reject_threshold = 6`
- **Recipient validation (PG):** `hosting/haraka/haraka_config/plugins/rcpt_to.host_list_base_shroud.js` → `SELECT domain FROM custom_domains`
- **shroud's SMTP server:** `lib/shroud/email/smtp_server.ex` (gen_smtp, `:1587`, `handle_RCPT` always accepts)
- **shroud's spam detection (header-only):** `lib/shroud/email/spam_handler.ex:25-32` + `get_spamassassin_header/1`
- **shroud's outbound relay:** `config/runtime.exs` → Swoosh `SMTP_RELAY=haraka`, port 25, TLS+auth
- **Haraka bounce handling:** `lib/shroud/email/bounce_handler.ex` (`handle_haraka_bounce_report/2`)
- **Timeline:** `hosting/.git/logs/HEAD` — Haraka added 2022-06-26 (`91095b86`), SpamAssassin same day (`8b877557`), PG recipient validation 2022-07-19 (`f7d2e961`)
- **MTA evolution:** `shroud.email/.git/packed-refs` — branches `use-postfix`, `use-haraka`, `remove-oh-my-smtp`, tag `own-relay`
