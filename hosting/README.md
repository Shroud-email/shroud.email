# Shroud.email hosting

Docker Compose configuration for self-hosting Shroud.email.

Clone the complete `Shroud-email/shroud.email` monorepo and run the commands below
from its `hosting/` directory. Do not copy this directory on its own: the Caddy
build also needs `../caddy-permissive-file-storage/`.

Please read our [deployment documentation](https://shroud.email/docs/deployment/self-host) on our website.

If you want to get up and running with Shroud.email quickly, and don't want to maintain your own mailserver, you can sign up for our hosted version [here](https://app.shroud.email/users/register).

Copy `haraka/haraka_config/config/me.example` to `haraka/haraka_config/config/me` and set your mail hostname.

## Running without third-party integrations

Copy `example.env` to `.env`, set your domains, database/SMTP passwords and
generated encryption/signing keys, then run `docker compose up -d --build`.
Cap, Sentry and Paddle are **not required**:

- Leave `COMPOSE_PROFILES`, `CAP_CADDYFILE` and the other `CAP_*` settings blank.
  Cap and Valkey will not start, and Caddy has no Cap route to parse or certify.
- Leave `SENTRY_DSN` blank or unset to disable error reporting.
- Leave all Paddle credentials blank or unset to disable Paddle billing.
  `PADDLE_ENVIRONMENT` can also be blank; it defaults to `live` when needed.
  Partial billing credentials still fail fast rather than silently disabling billing.

This does not change account entitlements: free accounts retain their existing
limits. The initial user created from `ADMIN_EMAIL` already has lifetime access
without using Paddle.

These application fixes need a newly built `web` image; the existing published
stable image will not gain them just by restarting. To use the checkout before
a release, build it locally and select it in `docker-compose.override.yaml`:

```sh
docker build -t shroud-web:local ../shroud.email
```

```yaml
services:
  web:
    image: shroud-web:local
```

When disabling Cap on an existing deployment, also stop its previously running
containers with `docker compose stop cap valkey`, then recreate the stack with
`docker compose up -d --build`. Disabling a profile does not stop existing containers.

## SMTP certificates

Caddy must obtain a certificate for `EMAIL_DOMAIN`, which should match the
mail hostname used by your MX record. Point its DNS at the server and allow
ACME validation (port 80 for the default HTTP-01 setup).

The certificate sidecar checks on startup and every minute, copies Caddy's
full chain and matching private key, and reloads Haraka after issuance or
renewal. Syncs are locked and validated pairs are published via an atomic
`current` symlink. Keep the shipped `tls.ini` paths (`certs/current/tls_key.pem`
and `certs/current/tls_cert.pem`) when upgrading a local configuration.
Until issuance succeeds, Haraka cannot advertise STARTTLS and the
web app's TLS-required SMTP delivery will retry. Missing certificates are not
a fatal Haraka error; check Caddy logs if they never appear.

Haraka is built locally by `--build`, including its required headers plugin.
The separate Haraka 3 upgrade is not required for these startup fixes.

Run `bash test.sh` from this directory to test Compose profiles, both Caddyfiles,
Haraka startup, and certificate issuance/renewal with local disposable containers.
The tests require Docker, Python 3 and OpenSSL; they do not request public certificates.

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

The compose file includes an optional [Cap](https://trycap.dev) self-hosted
CAPTCHA instance behind the `cap` Compose profile. Neither it nor Valkey runs
by default. The widget and verification also stay disabled until all three
`CAP_INSTANCE_URL`, `CAP_SITE_KEY` and `CAP_SECRET_KEY` settings are provided.

> **Public ingress required.** `CAP_INSTANCE_URL` must be a URL a user's
> browser can reach over HTTPS.

### Setup

1. Generate an admin key and set `CAP_ADMIN_KEY` in `.env`:
   ```bash
   openssl rand -hex 32
   ```

2. Set `COMPOSE_PROFILES=cap`, `CAP_DOMAIN` to your public CAPTCHA hostname,
   and `CAP_CADDYFILE=http.caddy` (or `bunny.caddy` with `BUNNY_API_KEY` for
   DNS-01). Create a DNS record for the hostname, then recreate the services:
   ```bash
   docker compose up -d --build cap valkey caddy
   ```

3. Create a site key.  Cap authenticates with a
   session token issued by logging in with the `ADMIN_KEY`. Create a `siteKey`
   and `secretKey` in the Cap UI at `https://CAP_DOMAIN`.

4. Set `CAP_INSTANCE_URL`, `CAP_SITE_KEY`, and `CAP_SECRET_KEY` in `.env`, then
   recreate `web` to apply the changed environment (a restart is not enough):
   ```bash
   docker compose up -d web
   ```
