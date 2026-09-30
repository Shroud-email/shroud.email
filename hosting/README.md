# Shroud.email hosting

Docker Compose configuration for self-hosting Shroud.email.

Clone the complete `Shroud-email/shroud.email` monorepo and run the commands below
from its `hosting/` directory. Do not copy this directory on its own: the Caddy
build also needs `../caddy-permissive-file-storage/`.

Please read our [deployment documentation](https://shroud.email/docs/deployment/self-host) on our website.

If you want to get up and running with Shroud.email quickly, and don't want to maintain your own mailserver, you can sign up for our hosted version [here](https://app.shroud.email/users/register).

Copy `haraka/haraka_config/config/me.example` to `haraka/haraka_config/config/me` and set your mail hostname.

## SMTP certificate sync

The Haraka upgrade alone does **not** activate copied certificates. This hosting
stack includes a separate certificate-sync fix in cron and Compose: it validates
and publishes a matching pair, sets `WITHOUT_CONFIG_CACHE=1` on Haraka and touches
its mounted `tls.ini`. This combination is tested on 3.3.4 for SNI and non-SNI
handshakes. If applying only the Haraka upgrade without that sync fix, validate
copied certificates and restart Haraka to activate them. Without a reload trigger,
copying new PEM files leaves the active default TLS context stale. Validate
complete key/chain pairs before publishing: malformed or mismatched input can
throw during context creation.
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
containers and Caddy route are disabled by default. Enable the `cap` Compose
profile and select a Cap Caddyfile, then set all three `CAP_*` variables on
`web` to render the widget and perform verification.

> **Public ingress required.** `CAP_INSTANCE_URL` must be a URL a user's
> browser can reach over HTTPS.

### Setup

1. Generate an admin key and set `CAP_ADMIN_KEY` in `.env`:
   ```bash
   openssl rand -hex 32
   ```

2. Choose a public hostname (for example, `cap.example.com`), set it as
   `CAP_DOMAIN` in `.env`, and create a DNS A/AAAA record pointing that hostname
   to this server. Set `COMPOSE_PROFILES=cap` and `CAP_CADDYFILE=http.caddy`
   (or `bunny.caddy` for Bunny DNS-01). When `CAP_CADDYFILE` is blank, Caddy
   imports the disabled configuration and does not expose a Cap route.

3. Start Cap and Caddy. Caddy reads `CAP_DOMAIN` when Compose creates the
   container and automatically provisions HTTPS for the hostname:
   ```bash
   docker compose up -d cap valkey caddy
   ```

4. Open `https://<CAP_DOMAIN>` and create a site key.  Cap authenticates with a
   session token issued by logging in with the `ADMIN_KEY`. Create a `siteKey` and `secretKey` in the Cap UI.

5. Set `CAP_INSTANCE_URL` in `.env` to the public URL
   (`https://<CAP_DOMAIN>`), set `CAP_SITE_KEY` to the `siteKey` returned by
   `/server/keys`, and set `CAP_SECRET_KEY` to its returned `secretKey`. Then
   recreate `web` so Compose applies the updated environment (`restart` does
   not refresh it):
   ```bash
   docker compose up -d web
   ```
