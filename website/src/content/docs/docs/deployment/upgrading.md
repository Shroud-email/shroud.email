---
title: Upgrading
description: How to update your Shroud.email deployment.
---

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
