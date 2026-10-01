---
title: Upgrading
description: How to update your Shroud.email deployment.
---

## SMTP certificate renewal migration

The certificate renewal fix changes Haraka from separate `tls_key.pem` and
`tls_cert.pem` files to a single `tls.pem` bundle containing the private key and
Caddy's full certificate chain. Haraka automatically activates future changes
without restarting, but existing installations need a **one-time manual migration**.
Running only `git pull` and restarting Haraka is not sufficient: the old cron
container does not create the new bundle until it is rebuilt.

Use a maintenance window and run these commands from the monorepo's `hosting/`
directory. SMTP will be unavailable while Haraka is stopped; other services can
remain running.

1. **Stop Haraka before pulling the update.** Its configuration is bind-mounted
   and watched live, so pulling first can make the running process switch to
   `tls.pem` before that file exists.

   ```sh
   docker compose stop haraka
   git pull
   ```

2. Rebuild and recreate cron, then publish the first certificate bundle. Only
   recreate Haraka if both commands succeed:

   ```sh
   docker compose up -d --build cron &&
   docker compose exec cron /etc/periodic/daily/bundle_certs &&
   docker compose up -d --force-recreate haraka
   ```

   If bundling fails, leave Haraka stopped, resolve the reported certificate or
   key error, and rerun this step. Do not start it without a valid `tls.pem`.

3. Check that Haraka is running and verify a STARTTLS connection to your mail
   hostname. The daily cron job will now publish renewed bundles automatically;
   Haraka activates them after the file watcher's five-second debounce and its
   one-second polling check. No manual restart is needed for future renewals.

## Version 1.0 breaking changes

On 2023-03-11, we released [Shroud.email version 1.0.0](https://github.com/Shroud-email/shroud.email/releases/tag/v1.0.0).
This version contains a potentially-breaking change that may break if you have several aliases with the same address, but different cases -- e.g. `alias@example.com` and `ALIAS@example.com`. We include a command to automatically merge aliases like this. This command needs to be run before you upgrade.

To deploy this version, follow these steps:

1. Update to version 0.2.4. Do this by changing the version in your `docker-compose.yml` to `ghcr.io/shroud-email/shroud.email:0.2.4` and then running

```
docker compose pull web && docker compose up --force-recreate -d
```

2. Once that is running, execute the following command:

```
docker compose exec web /home/elixir/app/bin/shroud rpc Shroud.Release.make_emails_case_insensitive
```

3. Update to version 1.0.0 by changing the version in your `docker-compose.yml` to `ghcr.io/shroud-email/shroud.email:1`, and re-running

```
docker compose pull web && docker compose up --force-recreate -d
```
