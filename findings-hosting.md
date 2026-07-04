# Haraka Recon — hosting repo (`/Users/tao/dev/shroud/hosting`)

Read-only inventory of Haraka's role in the shroud.email self-hosting stack.
All paths are relative to the hosting repo root unless noted.

## TL;DR

Haraka is the **public SMTP entry point** (ports 25 and 465) and does
substantially more than "forward SMTP to shroud". It owns:

- Inbound SMTP on **25** (plaintext, STARTTLS) and **465** (implicit TLS / SMTPS).
- **TLS termination** for both ports, using a Let's Encrypt cert minted by
  Caddy and copied in by the `cron` container (see TLS section).
- **SMTP AUTH** (CRAM-MD5 / PLAIN / LOGIN) against a single shared username/password
  from env (`SMTP_USERNAME` / `SMTP_PASSWORD`).
- **SpamAssassin** scanning of every inbound message via the **spamd** protocol
  over TCP to the `spamassassin` service on port 783.
- **Recipient validation** against the Postgres `custom_domains` table
  (plus the `EMAIL_DOMAIN` env var) — a custom plugin that queries the DB.
- **Sender/RCPT domain anti-spoof** (rejects mail FROM local domains from
  non-authenticated senders).
- **DNSBL / backscatterer** IP blocklisting on connect.
- **HELO checks**, **SPF**, **MAIL FROM is-resolvable** (MX), **headers** validation.
- **DKIM signing** of outbound mail (selector `shroudemail`, per-domain keys
  under `config/dkim/<domain>/`).
- **Outbound delivery** to the internet (Haraka's own `outbound` queue,
  `always_split=true`) — used for outgoing emails from shroud (commit
  `91095b8 use haraka for outgoing emails`).
- **Bounce logging** (custom `bounce_logger` plugin logs bounces as WARN).

Then it **forwards accepted inbound mail** to the shroud web app over plain
SMTP to `web:1587` (the `queue/smtp_forward` plugin, no TLS).

## Files Retrieved

1. `docker-compose.yaml` — full stack wiring (haraka, spamassassin, db, web, caddy, cron).
2. `docker-compose.override.example.yaml` — edge image + Watchtower (no haraka changes).
3. `haraka/Dockerfile` — `node:18.4-alpine3.16`, installs `Haraka@2.8.28` + `pg@8.7.3` globally, runs `haraka -c /app/haraka_config`.
4. `haraka/haraka_config/config/plugins` — plugin enable list (the authoritative order).
5. `haraka/haraka_config/config/smtp.ini` — listener config (all defaults commented out → port 25 default; `[headers]` raises `max_lines=1000`, `max_received=100`).
6. `haraka/haraka_config/config/smtp_forward.ini` — `host=web`, `port=1587`, `enable_tls=false`, `check_recipient=false`.
7. `haraka/haraka_config/config/spamassassin.ini` — `spamd_socket = spamassassin:783`, `max_size = 1000000`, `reject_threshold = 6`.
8. `haraka/haraka_config/config/tls.ini` — `key=certs/tls_key.pem`, `cert=certs/tls_cert.pem`.
9. `haraka/haraka_config/config/spf.ini` — `lookup_timeout = 10`.
10. `haraka/haraka_config/config/outbound.ini` — `always_split=true`, `pool_timeout=20` (Haraka outbound delivery).
11. `haraka/haraka_config/config/mail_from.is_resolvable.ini` — `timeout=20`, `allow_mx_ip=1`, `reject_no_mx=1`.
12. `haraka/haraka_config/config/host_list.anti_spoof` — contains `true`.
13. `haraka/haraka_config/config/me` — `Shroud.email` (Haraka's hostname / HELO name).
14. `haraka/haraka_config/config/log.ini` — `level=warn`.
15. `haraka/haraka_config/plugins/rcpt_to.host_list_base_shroud.js` — custom base plugin; queries Postgres `SELECT domain FROM custom_domains` and merges with `EMAIL_DOMAIN` env; also enforces anti-spoof on MAIL FROM.
16. `haraka/haraka_config/plugins/rcpt_to.in_host_list_shroud.js` — inherits the base; accepts RCPT TO if the recipient's domain is in the host list, or if the sender is a relayed local-sender.
17. `haraka/haraka_config/plugins/auth/environment_variable.js` — custom auth plugin (inherits `auth/auth_base`); advertises AUTH only on TLS/private-IP; returns `SMTP_PASSWORD` when `user === SMTP_USERNAME`.
18. `haraka/haraka_config/plugins/bounce_logger.js` — logs bounces as WARN on `hook_bounce`.
19. `haraka/haraka_config/config/dkim/dkim_key_gen.sh` — key generation helper, selector `shroudemail`.
20. `haraka/haraka_config/config/dkim/example.com/{selector,private,public,dns}` — **committed example DKIM keypair** (see Security note).
21. `cron/bundle_certs.sh` + `cron/Dockerfile` — daily cron that copies Caddy's ACME cert for `$EMAIL_DOMAIN` into the `pem_certs` volume as `tls_key.pem` / `tls_cert.pem` (bundled with `lets-encrypt-r4.pem`).
22. `caddy/Caddyfile` — Caddy obtains ACME certs for `$APP_DOMAIN` and `$EMAIL_DOMAIN`.
23. `README.md` — deployment pointer only; no Haraka-specific docs.

## Key config quoted

`config/plugins` (active lines only, in order):
```
dnsbl
backscatterer
helo.checks
tls
auth/environment_variable
mail_from.is_resolvable
spf
rcpt_to.in_host_list_shroud
headers
spamassassin
dkim_sign
bounce_logger
queue/smtp_forward
```

`config/smtp_forward.ini`:
```
host=web
port=1587
enable_tls=false
check_recipient=false
```

`config/spamassassin.ini`:
```
spamd_socket = spamassassin:783
max_size = 1000000
reject_threshold = 6
```

`config/tls.ini`:
```
key=certs/tls_key.pem
cert=certs/tls_cert.pem
```

`docker-compose.yaml` (haraka service):
```yaml
haraka:
  image: ghcr.io/shroud-email/haraka:main
  depends_on: [spamassassin, db]
  ports:
    - "25:25"
    - "465:465"
  environment:
    - EMAIL_DOMAIN=${EMAIL_DOMAIN}
    - SMTP_USERNAME=${SMTP_USERNAME}
    - SMTP_PASSWORD=${SMTP_PASSWORD}
    - PGHOST=db
    - PGUSER=${DB_USER}
    - PGPASSWORD=${DB_PASSWORD}
    - PGDATABASE=${DB_DATABASE}
  volumes:
    - ./haraka/haraka_config:/app/haraka_config
    - pem_certs:/app/haraka_config/config/certs
```

`web` service exposes `1587:1587` and gets `SMTP_RELAY=haraka`.

## Architecture — network topology

```
Internet (MX for EMAIL_DOMAIN + custom_domains)
        │  :25 (STARTTLS)  /  :465 (implicit TLS)
        ▼
   ┌─────────────────── Haraka (ghcr.io/shroud-email/haraka:main) ──────────────────┐
   │  dnsbl, backscatterer → helo.checks → tls → auth/env_var                       │
   │  → mail_from.is_resolvable → spf → rcpt_to.in_host_list_shroud (PG query)       │
   │  → headers → spamassassin (spamd TCP spamassassin:783) → dkim_sign              │
   │  → bounce_logger → queue/smtp_forward                                          │
   │                                                                                 │
   │  TLS certs:  /app/haraka_config/config/certs/{tls_key,tls_cert}.pem            │
   │              (populated by `cron` from Caddy's ACME store, via pem_certs vol)  │
   │  DKIM keys:  config/dkim/<domain>/{private,selector}                          │
   │  Outbound:   Haraka `outbound` queue (always_split) → MX delivery to internet  │
   │  DB conn:    PGHOST=db, queries custom_domains                                 │
   └───────────────────────────────┬────────────────────────────────────────────────┘
                                   │  plain SMTP, host=web port=1587, enable_tls=false
                                   ▼
                          shroud web (ghcr.io/shroud-email/shroud.email:1)
                                   │  SMTP_RELAY=haraka (for outgoing mail the app generates)
                                   │  :8080 → Caddy → app UI
                                   ▼
                              Postgres (db:5432)
```

Note the **two-way** relationship:
- Inbound internet → Haraka → `web:1587` (smtp_forward).
- Outbound shroud app → `haraka` (web's `SMTP_RELAY=haraka`) → Haraka `outbound` queue → internet MX.

## Every enabled plugin and what it does

| Plugin | Config | Role |
|---|---|---|
| `dnsbl` | defaults | DNS blocklist lookup on connect (uses Haraka's bundled `dnsbl.zones`). |
| `backscatterer` | defaults | Blocks IPs listed on backscatterer DNSBL. |
| `helo.checks` | defaults | HELO syntax/sanity checks. |
| `tls` | `tls.ini` → `certs/tls_key.pem`,`certs/tls_cert.pem` | STARTTLS on 25 and implicit TLS on 465; also gates AUTH. |
| `auth/environment_variable` (custom) | env `SMTP_USERNAME`/`SMTP_PASSWORD` | SMTP AUTH (CRAM-MD5/PLAIN/LOGIN); only advertised over TLS or from private IPs; single shared credential. |
| `mail_from.is_resolvable` | `mail_from.is_resolvable.ini`: `timeout=20 allow_mx_ip=1 reject_no_mx=1` | Rejects MAIL FROM whose domain has no MX/A record. |
| `spf` | `spf.ini`: `lookup_timeout=10` | SPF check on MAIL FROM. |
| `rcpt_to.in_host_list_shroud` (custom) → inherits `rcpt_to.host_list_base_shroud` (custom) | DB query + `EMAIL_DOMAIN` + `host_list.anti_spoof=true` | **Recipient validation against the database**: loads domain set from `SELECT domain FROM custom_domains` ∪ `EMAIL_DOMAIN`, accepts RCPT TO for local domains, allows relaying clients whose MAIL FROM is local. The base plugin also enforces anti-spoof on MAIL FROM (DENY if MAIL FROM domain is local but the connection isn't relaying). |
| `headers` | `smtp.ini [headers] max_lines=1000 max_received=100` | Header validity/limit checks. |
| `spamassassin` | `spamassassin.ini`: `spamd_socket=spamassassin:783 max_size=1000000 reject_threshold=6` | Scans every inbound message via the **spamd protocol over TCP** to the `dinkel/spamassassin` container on port 783; rejects when spam score ≥ 6. Messages > 1 MB are not scanned. |
| `dkim_sign` | keys under `config/dkim/<domain>/`, selector `shroudemail` | **Signs outbound mail** (selector file `selector`, `private` key per domain). Used for mail shroud itself sends out (outbound delivery via Haraka's `outbound` queue). |
| `bounce_logger` (custom) | — | `hook_bounce` logs the bounce error as WARN. |
| `queue/smtp_forward` | `smtp_forward.ini`: `host=web port=1587 enable_tls=false check_recipient=false` | The inbound queue plugin: delivers accepted messages to the shroud web app on port 1587 over plain SMTP. |

Notable **disabled** (commented) plugins: `karma`, `relay`, `access`, `p0f`, `geoip`, `asn`, `fcrdns`, `early_talker`, `data.uribl`, `attachment`, `clamd` (no ClamAV AV scanning), `limit` (no rate limiting), `bounce` (only the custom `bounce_logger`), `watch`.

## Ports

- **Haraka listens on `25` and `465`** (docker-compose maps both 1:1). `smtp.ini` has all `listen=` lines commented out, so Haraka defaults to port 25; **port 465 is implicit-TLS SMTPS** — note that Haraka's `tls` plugin enables TLS, but there is no explicit `listen=[::0]:465` in `smtp.ini`, so the 465 listener behavior comes from Haraka's default listener config inside the published image (the committed config only customizes `tls.ini`). Worth verifying against the image if 465 semantics matter.
- **587 is NOT Haraka.** `587` is exposed by the **web** container (`web:1587` → published `1587:1587`) and is the receive port Haraka forwards to internally. It is not a Haraka listener.

## SpamAssassin integration — yes, active today

- The `spamassassin` service (`image: dinkel/spamassassin`) is a separate container.
- Haraka's `spamassassin` plugin talks to it via the **spamd protocol over TCP**:
  `config/spamassassin.ini` → `spamd_socket = spamassassin:783`.
- `reject_threshold = 6` → messages scoring ≥ 6 are rejected.
- `max_size = 1000000` (1 MB) — larger messages skip scanning.
- The `spamassassin` service has `logging: { driver: none }`.
- Haraka `depends_on: [spamassassin, db]`.
- A leftover spooled message in `haraka/haraka_config/queue/...` shows SpamAssassin headers were applied (`"Checker-Version": "SpamAssassin 3.4.1 ..."`), confirming it runs in practice.

## TLS / Let's Encrypt handling

Haraka itself does **not** obtain certs. The flow:
1. **Caddy** acquires ACME certs for `$EMAIL_DOMAIN` (and `$APP_DOMAIN`) — `caddy/Caddyfile`.
2. The **`cron`** container (`cron/Dockerfile`, `bundle_certs.sh`) runs a daily cron job that copies Caddy's
   `${EMAIL_DOMAIN}.key` → `/pem/tls_key.pem` and concatenates `${EMAIL_DOMAIN}.crt` + `lets-encrypt-r4.pem`
   → `/pem/tls_cert.pem` (the R4 intermediate bundle).
3. The `pem_certs` named volume is mounted into Haraka at
   `/app/haraka_config/config/certs`, which `tls.ini` reads (`key=certs/tls_key.pem`,
   `cert=certs/tls_cert.pem`).

So **Haraka terminates TLS using Caddy-issued Let's Encrypt certs**, refreshed daily by the cron sidecar. Removal of Haraka means the cert-pipeline (`cron` + `pem_certs` volume + Caddy's `{$EMAIL_DOMAIN}` block) likely becomes unnecessary for SMTP (though Caddy still needs the cert for any HTTPS it serves).

## Other responsibilities beyond "forward SMTP to shroud"

- **Recipient validation against Postgres** (`rcpt_to.in_host_list_shroud` → `custom_domains` table + `EMAIL_DOMAIN`). This is real business logic — Haraka is the authority for "is this recipient address one of our domains" before shroud ever sees the message.
- **Anti-spoof** on MAIL FROM (`host_list.anti_spoof=true`): rejects external senders claiming to be from a local domain.
- **DNSBL + backscatterer** IP reputation blocking on connect.
- **SPF**, **MAIL FROM MX-resolvable**, **HELO checks**, **header limits**.
- **SpamAssassin spam scoring + rejection**.
- **DKIM signing of outbound mail** (selector `shroudemail`, per-domain keys committed under `config/dkim/`).
- **Outbound delivery to the internet** via Haraka's own `outbound` queue (`outbound.ini` `always_split=true`). The shroud web app points `SMTP_RELAY=haraka`, so outgoing mail from the app flows through Haraka, which signs (DKIM) and delivers to MX. Removing Haraka breaks both inbound receipt **and** outbound sending — the app would need a new SMTP relay and a separate DKIM signer.
- **Bounce logging** (custom `bounce_logger`).
- **SMTP AUTH** gateway (single shared credential).

## Security note (not Haraka-removal-specific, but worth flagging)

`haraka/haraka_config/config/dkim/example.com/private` is a **committed RSA private key**
(generated by `dkim_key_gen.sh` as an example). It's labelled `example.com`, so it is
not the production key, but it is a real 2048-bit private key checked into git. The
production DKIM key for the real `EMAIL_DOMAIN` would live in `config/dkim/<domain>/`
(only `example.com` is committed here; the real domain's keys are presumably mounted
at deploy time or baked into the `ghcr.io/shroud-email/haraka:main` image). Severity: low
for production (it's an example key), but a committed private key is a smell — the
`example.com` keypair should probably be removed from history.

## Start here

Open `haraka/haraka_config/config/plugins` first — it is the single source of truth for
what Haraka runs and in what order. Then `docker-compose.yaml` (haraka + spamassassin + db
+ web services) for the wiring, and `config/smtp_forward.ini` for the forward target.

## Implications for Haraka removal (preview)

If Haraka is removed, the following capabilities must be re-homed:
1. Public SMTP listeners on 25/465 (TLS termination).
2. SMTP AUTH (CRAM-MD5/PLAIN/LOGIN) against `SMTP_USERNAME`/`SMTP_PASSWORD`.
3. SpamAssassin spamd scanning (or drop it).
4. Recipient validation against Postgres `custom_domains` + `EMAIL_DOMAIN`.
5. Anti-spoof, SPF, MX-resolvable, HELO, header-limit, DNSBL/backscatterer checks.
6. DKIM signing of outbound mail.
7. Outbound MX delivery (the web app's `SMTP_RELAY=haraka`).
8. Bounce logging.
9. TLS cert pipeline from Caddy (the `cron` `pem_certs` volume).

Today shroud web already exposes `:1587` and receives forwarded mail from Haraka; if shroud
could listen directly on 25/465 with its own TLS, AUTH, recipient validation, DKIM signing,
and outbound delivery, Haraka becomes redundant. The DB query (`SELECT domain FROM custom_domains`)
and the `EMAIL_DOMAIN` env check are the only pieces of custom logic that would have to move
into the shroud app (or a successor MTA config).

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Concrete findings with exact file paths and quoted config lines throughout (e.g. config/plugins, smtp_forward.ini, spamassassin.ini, docker-compose.yaml haraka service). Security finding (committed DKIM private key) flagged with file path haraka/haraka_config/config/dkim/example.com/private."
    }
  ],
  "changedFiles": [],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    { "command": "ls / read over haraka/, docker-compose.yaml, cron/, caddy/", "result": "passed", "summary": "Read-only recon; no modifications made." }
  ],
  "validationOutput": [
    "Report written to /Users/tao/dev/shroud/shroud.email/.worktrees/explore-haraka-removal/findings-hosting.md"
  ],
  "residualRisks": [
    "Haraka image is ghcr.io/shroud-email/haraka:main (prebuilt); the committed haraka_config volume overrides it, but any default listener config baked into the image (e.g. 465 implicit TLS) was not verifiable from this repo alone — verify against the image if 465 semantics matter.",
    "Committed RSA private key at haraka/haraka_config/config/dkim/example.com/private (example domain, not production) — low severity but a smell.",
    "The real EMAIL_DOMAIN DKIM private key is not in this repo; assumed mounted at deploy or baked into the image — removal plan must account for where production DKIM keys live.",
    "Outbound delivery (web SMTP_RELAY=haraka → Haraka outbound queue → MX) is a second dependency on Haraka beyond inbound forwarding; removing Haraka breaks outbound sending too."
  ],
  "noStagedFiles": true,
  "diffSummary": "No changes — read-only recon. Findings written to the designated output path.",
  "reviewFindings": [
    "no blockers (read-only task)",
    "low: haraka/haraka_config/config/dkim/example.com/private — committed RSA private key (example domain)"
  ],
  "manualNotes": "Haraka is NOT a thin forwarder: it owns TLS, AUTH, SpamAssassin (spamd TCP spamassassin:783), DB-backed recipient validation, anti-spoof, SPF, DNSBL, DKIM signing, and outbound MX delivery. Two-way dependency with the web app: inbound internet→Haraka→web:1587, and outbound web→Haraka→internet. Removing Haraka requires re-homing all of these, most critically the custom_domains PG recipient check and outbound DKIM signing/delivery."
}
```
