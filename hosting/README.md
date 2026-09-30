# Shroud.email hosting

Docker Compose configuration for self-hosting Shroud.email.

Clone the complete `Shroud-email/shroud.email` monorepo and run the commands below
from its `hosting/` directory. Do not copy this directory on its own: the Caddy
build also needs `../caddy-permissive-file-storage/`.

Please read our [deployment documentation](https://shroud.email/docs/deployment/self-host) on our website.

If you want to get up and running with Shroud.email quickly, and don't want to maintain your own mailserver, you can sign up for our hosted version [here](https://app.shroud.email/users/register).

Copy `haraka/haraka_config/config/me.example` to `haraka/haraka_config/config/me` and set your mail hostname.

## Haraka 3 upgrade

Haraka is pinned to **3.3.4**, the latest stable release checked on 2026-09-30
against both the [upstream GitHub release](https://github.com/haraka/Haraka/releases/tag/v3.3.4)
and the [npm `latest` tag](https://www.npmjs.com/package/Haraka). The image uses
Node 24 LTS; Haraka itself requires Node 20+, but its current build dependencies
require a newer Node patch release. Haraka, the active external plugins, and
PostgreSQL client dependencies are locked in `haraka/haraka_config/package-lock.json`.
They are installed under `/app/node_modules`, outside the Compose configuration
bind mount.

When upgrading an existing installation, migrate its local configuration too:

- `dnsbl` and `backscatterer` become one `dns-list` plugin. Move custom DNS zones
  and rejection settings into `dns-list.ini`; the committed configuration keeps
  the old Spamhaus list and enables the null-sender/postmaster backscatter check.
- `dkim_sign` becomes `dkim`. Move local `dkim_sign.ini` settings into `[sign]`
  in `dkim.ini`: `disabled=false` becomes `enabled=true`, and `headers_to_sign`
  becomes `headers`. The existing `config/dkim/<domain>/private` and `selector`
  files still work. Signing remains opt-in, as in 2.8.28; verification remains
  disabled unless deliberately enabled under `[verify]`.
- Header settings, SMTPUTF8 and strict RFC 1869 settings move from `smtp.ini` to
  `connection.ini`. Migrate old greeting, UUID, message-size and line-limit files
  using the [upstream migration table](https://github.com/haraka/Haraka/blob/v3.3.4/CHANGELOG.md#310---2025-01-30).
  Keep the new `max`, `message` and `uuid` sections: missing sections can break
  SMTP sessions. The committed message-size limit is 25 MiB.
- `mail_from.is_resolvable.ini` uses `timeout_ms` and `[reject] no_mx=deny`;
  the committed configuration retains the 20-second DNS timeout.

To verify without publishing or starting the deployment stack:

```sh
docker build -t shroud-haraka:local haraka
docker run --rm shroud-haraka:local --version
```

The build runs the Node compatibility tests, including SMTP STARTTLS/AUTH,
recipient/relay decisions, DKIM signing and TLS certificate rotation. To run
them outside Docker, use Node 24.15+ and OpenSSL, then run `npm ci --omit=optional`
and `npm test` from `haraka/haraka_config/`.

The upgrade alone does **not** activate copied certificates. The coordinated
certificate-sync fix uses `WITHOUT_CONFIG_CACHE=1` and touches mounted `tls.ini`
after publishing a valid pair; this combination is tested on 3.3.4 for SNI and
non-SNI handshakes. Without a reload trigger, copying new PEM files still leaves
the active default TLS context stale. Validate complete key/chain pairs before
publishing: malformed or mismatched input can throw during context creation.
The SMTP certificate must cover the actual MX hostname, including for clients
that do not send SNI.

Haraka 3.3.4 does not add outbound MTA-STS enforcement. Inbound MTA-STS also still
needs its HTTPS policy host, discovery TXT records, and a valid MX certificate;
these are separate follow-up work, not enabled by this upgrade.

## TLS via Bunny DNS-01 (optional)

Caddy defaults to HTTP-01 ACME (port 80), which works behind no other reverse
proxy. If your setup needs DNS-01 (e.g. you can't open port 80, or you want
wildcard certs), opt in to the Bunny.net DNS challenge:

1. Set `BUNNY_API_KEY` in `.env` to your Bunny.net account API key.
2. Set `CADDYFILE_PATH=./caddy/Caddyfile.bunny` in `.env`.
3. `docker compose up -d --build caddy`.

The Caddy binary is built locally (see `caddy/Dockerfile`) with both the
`caddy-permissive-file-storage` and `caddy-dns/bunny` modules. Self-hosters who
leave the defaults get HTTP-01 and never need a Bunny key.

## Living on the edge

The committed `docker-compose.yaml` tracks the stable image. If you'd rather
run the latest `:edge` build (rebuilt when the app changes on `main`) and have it
auto-update, copy the example override and bring the stack up:

```
cp docker-compose.override.example.yaml docker-compose.override.yaml
docker compose up -d
```

This points the `web` service at `:edge` and adds [Watchtower](https://containrrr.dev/watchtower/),
which polls every 5 minutes and auto-recreates `web` (and only `web`) when a new
image is published.

## Cap CAPTCHA

The compose file includes a [Cap](https://trycap.dev) self-hosted CAPTCHA
instance. It is **opt-in at the application level**: the
services run by default, but the widget is not rendered and verification
is not performed until you set all three `CAP_*` variables on the `web`
service.

> **Public ingress required.** `CAP_INSTANCE_URL` must be a URL a user's
> browser can reach over HTTPS.

### Setup

1. Generate an admin key and set `CAP_ADMIN_KEY` in `.env`:
   ```bash
   openssl rand -hex 32
   ```

2. Start the services:
   ```bash
   docker compose up -d cap valkey
   ```

3. Create a site key.  Cap authenticates with a
   session token issued by logging in with the `ADMIN_KEY. Create a `siteKey` and `secretKey` in the Cap UI.

4. Set `CAP_INSTANCE_URL`, `CAP_SITE_KEY`, and `CAP_SECRET_KEY` in `.env`, then
   restart `web`:
   ```bash
   docker compose restart web
   ```
