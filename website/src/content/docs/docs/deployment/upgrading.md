---
title: Upgrading
description: How to update your Shroud.email deployment.
---

## Version 1.4.0: Required manual changes

Existing installations need a one-time migration to the `tls.pem` certificate
bundle and must activate the custom-domain DKIM plugin. Update both the Haraka
image and the production checkout: Compose mounts
`hosting/haraka/haraka_config` over the configuration bundled in the image, so
pulling the image alone does not activate the plugin.

Your existing DKIM configuration must include a valid installation key at
`haraka/haraka_config/config/dkim/<EMAIL_DOMAIN>/private`, a sibling `selector`
file containing `shroudemail`, and the matching public TXT record at
`shroudemail._domainkey.<EMAIL_DOMAIN>`. Preserve these files when updating the
checkout; **do not regenerate a working key**.

Run from `hosting/` during a maintenance window. **Stop Haraka before updating
the checkout** to prevent its live configuration from referencing a certificate
bundle that does not yet exist:

```sh
docker compose stop haraka &&
git pull --ff-only &&
docker compose pull haraka &&
docker compose up -d --build cron &&
docker compose exec cron /etc/periodic/daily/bundle_certs &&
docker compose up -d --no-deps --force-recreate haraka
```

If a command fails, leave Haraka stopped until resolved. Check startup logs with
`docker compose logs --tail=100 haraka`.

Send both a forwarded message and an alias reply through a custom domain to an
external inbox. Confirm that `DKIM-Signature` contains `d=<custom-domain>` and
`s=shroudemail`, and that the recipient's `Authentication-Results` reports
`dkim=pass`. Custom-domain owners must publish the DKIM CNAME shown in the app;
existing matching CNAMEs need no changes.

These Haraka changes require no database migrations, new environment variables, or
per-custom-domain key provisioning. Certificate renewals activate automatically
without restarting Haraka, and ownership-verified custom domains use the
installation's DKIM key without per-domain files or restarts.

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
