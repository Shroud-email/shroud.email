# Shroud.email hosting

Docker Compose configuration for self-hosting Shroud.email.

Clone the complete `Shroud-email/shroud.email` monorepo and run the commands below
from its `hosting/` directory. Do not copy this directory on its own: the Caddy
build also needs `../caddy-permissive-file-storage/`.

Please read our [deployment documentation](https://shroud.email/docs/deployment/self-host) on our website.

If you want to get up and running with Shroud.email quickly, and don't want to maintain your own mailserver, you can sign up for our hosted version [here](https://app.shroud.email/users/register).

Copy `haraka/haraka_config/config/me.example` to `haraka/haraka_config/config/me` and set your mail hostname.

## Custom-domain DKIM

Generate and publish the `EMAIL_DOMAIN` DKIM key using the deployment guide and
`haraka/haraka_config/config/dkim/dkim_key_gen.sh`. The local `dkim_shroud` plugin
automatically signs for custom domains whose ownership was verified within the
last 24 hours, using this same private key and selector while retaining the
custom domain as the signature's `d=` value. Customers publish the DKIM CNAME
shown in the app; no per-customer keys, files or restarts are required.

The plugin was imported from `haraka-plugin-dkim` 1.3.1 with its MIT license.
Signing and verification code remain upstream; custom-domain key selection uses
PostgreSQL through the existing Haraka database environment variables. Unknown
or expired domains are not signed. Lookup errors and missing keys are logged
and mail continues without a signature, preserving upstream behavior.

After updating an existing installation, rebuild/recreate Haraka to activate the
plugin. Test both a forwarded message and an alias reply at an external inbox:
the signature should have `d=<custom domain>; s=shroudemail`, and the recipient's
`Authentication-Results` should report `dkim=pass`.

Regression tests:

```sh
cd haraka/haraka_config
npm ci --omit=dev --omit=optional
node --test test/*.test.js
```

## SMTP certificate renewal

The daily cron job publishes Caddy's certificate and matching private key as one
validated, atomically replaced `tls.pem` bundle. Haraka's `tls_cert_reload` plugin
checks Haraka's cached bundle every second and activates changes for new STARTTLS
connections after the file watcher's five-second debounce. It does not restart
the SMTP server or interrupt existing connections.

When upgrading from the old separate PEM files, use a maintenance window. Stop
Haraka **before updating the checkout**: its bind-mounted `tls.ini` is watched
live and will otherwise switch to the new bundle before that file exists.
After updating the checkout, rebuild cron, publish the first bundle, and recreate
Haraka once to load the new plugin and TLS configuration. Only start Haraka if
publication succeeds:

```sh
# Before updating the checkout:
docker compose stop haraka
# Update the checkout, then:
docker compose up -d --build cron &&
docker compose exec cron /etc/periodic/daily/bundle_certs &&
docker compose up -d --force-recreate haraka
```

Regression test (requires Node.js and OpenSSL):

```sh
cd haraka/haraka_config
npm ci --omit=dev --omit=optional
node --test test/tls_cert_reload.test.js
```

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
