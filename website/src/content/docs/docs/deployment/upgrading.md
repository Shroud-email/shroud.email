---
title: Upgrading
description: How to update your Shroud.email deployment.
---

## Version 1.4.0: SMTP certificate renewal migration

Existing installations need a one-time migration to the new `tls.pem` bundle.
Run from `hosting/` during a maintenance window. **Stop Haraka before pulling**
to prevent its live configuration from referencing a bundle that does not yet exist:

```sh
docker compose stop haraka &&
git pull &&
docker compose up -d --build cron &&
docker compose exec cron /etc/periodic/daily/bundle_certs &&
docker compose up -d --force-recreate haraka
```

If a command fails, leave Haraka stopped until resolved. Future certificate
renewals activate automatically without restarting Haraka.

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
