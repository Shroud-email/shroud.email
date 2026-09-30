# Monorepo migration

## Source provenance

All imports preserve original commits through unsquashed subtree merges. Each
import's tree was compared to its source tree before migration-specific edits.
Existing app tags retain their original objects.

| Project | Source revision |
| --- | --- |
| shroud.email | [9635750](https://github.com/Shroud-email/shroud.email/commit/9635750) |
| website | [e82132e](https://github.com/Shroud-email/website/commit/e82132ec605b9bf88578008b1facd8ebf6d8c2f6) |
| hosting | [afa908b](https://github.com/Shroud-email/hosting/commit/afa908b2498bf2ed7b181d029130d0c61cc69069) |
| email-trackers | [deeef41](https://github.com/Shroud-email/email-trackers/commit/deeef41f9c48bd8d25c0ff300e967f4ea8a292b1) |
| caddy-permissive-file-storage | [4059a60](https://github.com/Shroud-email/caddy-permissive-file-storage/commit/4059a602db55a1762de165dac7f1204c823ebbd4) |

Historical files keep their original paths in original commits. Use the source
revision above with `git log <revision> -- <original-path>` to inspect pre-import
history. Do not squash or rebase away the import merge commits when integrating
this branch. Use a history-preserving merge.

Issues, PRs, release assets, secrets, and repository settings are not imported.
Keep the old repositories available for external source/module consumers during
cutover. The Go module identity is unchanged; hosting builds use a local source
replacement rather than fetching the old repository.

## App release continuity

The release manifest starts at the existing app version `1.3.0`, with unprefixed
`vX.Y.Z` tags and the `v1.3.0` commit as the bootstrap boundary. Only the
`shroud.email/` package is released. Sentry and image builds use the same
first-parent app-tag description; other projects' tags were not imported.

Unreleased app commits before the move have root-relative paths, so manifest
path filtering cannot associate them with `shroud.email/`. The migration's
`docs: preserve app release history across relocation` commit carries their
six releasable messages as release-please conventional-commit footers. This
preserves their feature/fix entries and the next minor-version bump without
rewriting the original commits or leaving a permanent `release-as` override.
Review the first release PR's notes before merging it. The original unreleased
range, including the Sentry fix incorporated by rebasing, is `v1.3.0..77c286f`;
dependency/build/chore commits remain in that history.

## GitHub cutover (not performed by this migration)

1. Keep the source repositories available. Disable their old publishing workflows
   and let in-flight deployments finish before merging/enabling the replacements.
   This includes website production/staging, tracker publishing, Haraka, and the
   standalone Caddy image. Do not let both old and new repositories publish.
2. Copy secret values through GitHub's secure settings, using the mapping below.
   Values cannot be recovered through the GitHub API; an owner must supply them.
   Website production/staging and trackers share the account-level `BUNNY_API_KEY`.
   Configure it once; storage passwords and script deployment keys stay separate.
3. Grant `Shroud-email/shroud.email` Actions write access to existing GHCR packages
   `haraka` and `caddy-permissive-file-storage`. The app package name is unchanged.
4. Preserve the app's existing secrets (`PAT`, `CODECOV_TOKEN`, `SENTRY_AUTH_TOKEN`,
   `SENTRY_ORG`, `SENTRY_PROJECT`). Ensure the PAT can create release PRs/releases
   in the destination. Inspect any open pre-migration release PR before cutover;
   do not merge its obsolete root paths into the relocated app.
5. Merge with history preserved, not squash/rebase. Existing app check names and
   workflow filenames remain. Imported checks now appear under `Hosting images`
   and `Caddy module`; update required-check rules if those are required. PR build
   workflows deliberately run without path filters to avoid pending checks.
6. Validate production/staging deployments and image publishing in GitHub after
   authorization. The first monorepo merge changes every project, so its push can
   trigger path-filtered production deployments and image publishing. Staging is
   manual-only; after the merge, dispatch its workflow separately against `main`.
   Prepare secrets and package access first.

| Source repository | Old secret | Destination secret |
| --- | --- | --- |
| website | `BUNNY_STORAGE_PASSWORD` | `WEBSITE_BUNNY_STORAGE_PASSWORD` |
| website | `BUNNY_PULLZONE_ID` | `WEBSITE_BUNNY_PULLZONE_ID` |
| website | `BUNNY_API_KEY` | `BUNNY_API_KEY` |
| website | `BUNNY_SCRIPT_ID` | `WEBSITE_BUNNY_SCRIPT_ID` |
| website | `BUNNY_DEPLOY_KEY` | `WEBSITE_BUNNY_DEPLOY_KEY` |
| website | `BUNNY_STAGING_STORAGE_PASSWORD` | `WEBSITE_BUNNY_STAGING_STORAGE_PASSWORD` |
| website | `BUNNY_STAGING_PULLZONE_ID` | `WEBSITE_BUNNY_STAGING_PULLZONE_ID` |
| website | `BUNNY_STAGING_SCRIPT_ID` | `WEBSITE_BUNNY_STAGING_SCRIPT_ID` |
| website | `BUNNY_STAGING_DEPLOY_KEY` | `WEBSITE_BUNNY_STAGING_DEPLOY_KEY` |
| email-trackers | `BUNNY_STORAGE_PASSWORD` | `TRACKERS_BUNNY_STORAGE_PASSWORD` |
| email-trackers | `BUNNY_PULLZONE_ID` | `TRACKERS_BUNNY_PULLZONE_ID` |
| email-trackers | `BUNNY_API_KEY` | `BUNNY_API_KEY` |

Application, Haraka, and standalone Caddy image identities are still
`ghcr.io/shroud-email/shroud.email`, `ghcr.io/shroud-email/haraka`, and
`ghcr.io/shroud-email/caddy-permissive-file-storage`. Website and tracker Bunny
zones/URLs are unchanged. Staging refs must now contain the monorepo layout.

## Local validation

Both orb setup passes completed, including a warm pass; the relocated Phoenix
preview responded with HTTP 302. The app suite passed 552 tests, and formatting
and compilation with warnings-as-errors passed. The website built 27 pages;
the edge script type-check and bundle passed. Seven local workflow contract
checks covered project selection, tag builds, PR publishing guards, staging refs,
secret/concurrency separation, scheduled image selection, and local Caddy source.

Additional checks passed:

- `actionlint` with the repository's Blacksmith runner labels configured.
- `mise exec -- zizmor --offline .github/workflows`: no findings.
- `mise exec -- pinact run --fix=false --no-api`: all action references pinned.
  This is an offline syntax check, not remote tag/SHA verification.
  Bunny's `deploy-script@0.5.0` tag format is unsupported by pinact 4.1;
  `.pinact.yaml` exempts only its exact SHA. The annotated tag was independently
  resolved through GitHub's API to that SHA. Review Bunny action updates manually.
- `mix coveralls.json`: 552 tests passed, 76.3% coverage; all 134 reported source
  paths resolve under the app directory. Root `codecov.yml` prefixes upload paths.
- Production image E2E: two Playwright journeys passed, including alias lifecycle
  and mail forwarding. The Docker harness removed its disposable services.
- Caddy module E2E: certificate/key files 0644 and directories 0755, excluding locks.
- Local Docker builds for Haraka, standalone Caddy, and hosting Caddy. The latter
  lists both `caddy.storage.permissive_file_storage` and `dns.providers.bunny`.
- Compose configuration validation with the example environment (unset optional
  variables warn); no hosting services were started.
- Tracker publishing exercised with fake credentials and intercepted requests:
  exact list bytes, existing destination, and upload-before-purge ordering.
- Release config JSON schema and actual release-please parsing/versioning:
  the compatibility commit contributes five entries and computes `1.4.0` from
  `1.3.0`, while unrelated project commits are excluded.
- Rebuilt website documentation: browser DOM checks confirmed the new clone and
  working-directory instructions and issue link; the self-host page screenshot
  was inspected for readable commands and the sibling-module note.

Strict Credo reports 51 readability issues and 13 design suggestions in unchanged
app files. Sobelow reports six existing findings: traversal in
`failed_email_exporter.ex` (two) and `mailer.ex` (one), plus `send_resp` (two) and
content-type (one) findings in `proxy_controller.ex`. The app's `lib/`, `test/`,
and Sobelow configuration trees match the pre-migration revision exactly; these
findings were not fixed or suppressed as part of moving the project.

No GitHub workflows, release creation, production uploads, package publishing,
or secret/permission changes were executed locally.
