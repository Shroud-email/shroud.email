# Shroud.email hosting

Docker Compose configuration for self-hosting Shroud.email.

Please read our [deployment documentation](https://shroud.email/docs/deployment/self-host) on our website.

If you want to get up and running with Shroud.email quickly, and don't want to maintain your own mailserver, you can sign up for our hosted version [here](https://app.shroud.email/users/register).

Copy `haraka/haraka_config/config/me.example` to `haraka/haraka_config/config/me` and set your mail hostname.

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
run the latest `:edge` build (rebuilt on every push to `main`) and have it
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
