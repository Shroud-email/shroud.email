# Shroud.email monorepo migration

## Goal and agreed layout

Combine all five repositories in the Shroud-email GitHub organization into the
existing `Shroud-email/shroud.email` repository. The user prefers sibling project
directories over leaving the Phoenix application at the repository root.
Preserve each project's existing automation and runtime behavior; centralize
repository-wide automation where it removes duplication.

```text
.github/workflows/                 All active GitHub Actions workflows
.agents/                          Monorepo orb setup and resume entrypoints
.amp/services.yaml                Monorepo development services
docs/                             Migration and shared documentation
shroud.email/                     Phoenix application, assets, tests, Dockerfile
website/                          Astro website and Bunny edge script
hosting/                          Self-hosting Compose stack and image sources
email-trackers/                   Tracker list and publishing script
caddy-permissive-file-storage/    Caddy storage module and integration tests
```

Root documentation explains the projects and their commands. Root tooling owns
commitlint, Husky, pinact, and zizmor. Project directories retain their own
language dependencies, lockfiles, licenses, build configuration, and ignore rules.
There is no new cross-language build framework or shared package workspace.

## Scope and delivery boundary

Prepare and verify the migration locally in this checkout. Do not push, deploy,
change GitHub secrets or settings, archive repositories, or disable existing
workflows without separate authorization. Runtime features and page appearance
remain unchanged. Existing container names, app release versions, tracker-list
URL, website domains, and Bunny deployment destinations remain unchanged.

The old repositories remain available during the cutover, particularly for
external consumers of the old Go module path or tracker source URL. Issues,
pull requests, release assets, repository settings, and secrets are not Git data
and are not imported by this migration.

## Git history

Keep the existing application's history and release tags. Move its tracked
project files in a dedicated commit, separating relocation from path corrections.
Import each other repository's default-branch history with an unsquashed subtree
merge under its sibling directory. This keeps original commits reachable without
rewriting their IDs or rewriting the destination's published history. Record the
source repository and imported revision for each project in the migration notes.

Historical commits retain their original paths; the import does not promise
rewritten, directory-prefixed history for every historical revision. Do not
import unrelated projects' tags into the app's release-tag namespace. Preserve
source licenses and attribution. Copy tracked source only, not source `.git`
directories, credentials, dependencies, build outputs, or local environment files.

## Project and developer tooling boundaries

Move Phoenix-specific configuration, scripts, E2E infrastructure, assets, and
documentation under `shroud.email/`. Keep repository-level commitlint/Husky npm
dependencies and their lockfile at the root, since they manage the single Git
repository rather than the Phoenix runtime.

Use root mise configuration for common maintenance tools. Keep distinct project
runtime versions where needed: the website uses Node 22, pnpm, and Deno, while
the app uses its existing Elixir/Erlang and Node toolchain. Remove duplicate
pinact/zizmor declarations from imported project configuration. Give the Caddy
module an explicit Go toolchain consistent with its existing workflow.

Adapt root orb setup/resume entrypoints and service commands to the new paths.
Reuse existing setup routines where practical, with explicit project working
directories. Preserve the working Phoenix preview and website development setup.
Scope existing Phoenix guidance to the app directory; retain website guidance
within the website and provide concise root navigation guidance.

## GitHub Actions

GitHub only discovers workflows directly under the root `.github/workflows/`.
Relocate imported workflows there, give them unambiguous project-specific names,
and remove duplicate nested workflow definitions from the imported working tree.

Preserve the following responsibilities:

| Project | Responsibilities |
| --- | --- |
| App | Elixir checks, coverage, production-image E2E, multi-architecture images, release-please, Sentry releases, Sobelow |
| Website | Production site and edge-script deployment; manually selected staging ref |
| Hosting | Haraka image build and publishing |
| Trackers | Bunny list publishing |
| Caddy | Go/Caddy integration tests and container publishing |
| Shared | Commit title linting, zizmor, Trivy repository scan and scheduled app-image scan |

Update shell working directories, action input paths, Docker build contexts,
lockfile/cache paths, artifact locations, and SARIF/coverage paths independently.
GitHub Actions `defaults.run.working-directory` does not affect action inputs.
Scope caches and deployment concurrency groups by project to avoid collisions.

Use project path filters on push-triggered builds/deployments, including their
workflow files and any shared inputs they consume. Preserve manual deployment
entrypoints and app release-tag builds. Required PR checks must still report a
result for unrelated changes: use job-level change selection with a stable
completion check where needed rather than leaving required workflows pending.
The cutover notes must identify any required-check name changes.

Run zizmor once across all active workflows and maintain action pins centrally.
Keep project build/deployment workflows separate rather than introducing a
generic deployment abstraction. Do not couple website and tracker deployments
through their currently identical `deploy-bunny` concurrency group.

Publishing jobs must not publish containers or deploy from pull requests. The
hosting workflow currently sets `push: true` on PR runs; preserve its PR build
coverage but restrict login/publishing to trusted push events as part of moving
that workflow. Preserve minimal permissions and disabled checkout credentials.

## Release and deployment compatibility

Configure release-please for the app's new `shroud.email/` path while preserving
its existing release version and tag convention. Unrelated component changes
must not create app releases. App Docker metadata and Sentry version computation
must continue to agree, and imported history must not contaminate tag selection.

Explicitly preserve these image destinations rather than deriving all names from
the monorepo's `github.repository` value:

- `ghcr.io/shroud-email/shroud.email`
- `ghcr.io/shroud-email/haraka`
- `ghcr.io/shroud-email/caddy-permissive-file-storage`

Path-filtered app builds mean the latest monorepo commit may have no corresponding
app image. The scheduled image scan must scan the existing app `edge` image,
rather than assume `sha-<current monorepo commit>` was published.

Website and tracker deployments currently reference identically named Bunny
secrets with different destination credentials. Use project-prefixed secret names
in the consolidated workflows, with an explicit old-to-new name mapping in the
cutover notes. Include website staging credentials in that mapping. Per the
owner's clarification, share one account-level `BUNNY_API_KEY` secret across
website production/staging and trackers. Never copy or
print secret values. Preserve the app's existing secrets where no collision
exists. Document destination-repository permissions needed to publish existing
GHCR packages.

Hosting currently builds Caddy by fetching the old plugin module from GitHub.
Change its build context and Dockerfile to use the sibling plugin source with
xcaddy's local replacement mechanism. Retain the plugin's current Go module
identity for compatibility; changing its public module path is not required to
build the monorepo. Plugin edits must also be included in relevant hosting build
dependencies. Compose commands remain usable from `hosting/`.

## Verification and acceptance

Before implementation, inventory tracked files and source revisions for all five
repositories. After import, compare each imported source tree against its source
revision, accounting for explicitly reviewed migration edits. Confirm source
histories remain reachable and the app's existing tags remain intact.

Validate all consolidated workflows with actionlint and zizmor; inspect trigger,
permission, cache, artifact, and deployment-destination behavior. Run pinact's
available validation/check mode, or inspect full commit pins without modifying
unrelated dependency versions. Verify path selection for app-only, website-only,
tracker-only, hosting-only, plugin-only, shared-workflow, and release-tag changes.

Run the app's formatting, compile, tests, lint/security checks, and production
image E2E from its new directory. Build the website and type-check/bundle the edge
script without deploying. Run Caddy integration tests and build affected Docker
images locally. Validate Compose configuration using disposable placeholder
configuration, never shared services or production credentials. Check tracker
publishing paths without making upload requests. Verify root hooks and orb
entrypoints resolve their new project paths.

Record actual commands and failures; do not report CI execution or live
deployments as verified by static checks. Any check blocked by unavailable tools,
network access, or credentials must be reported explicitly.

Acceptance requires all five source trees, reachable imported histories,
preserved automation responsibilities, no accidental publishing on PRs, and clear
cutover instructions for external state. GitHub-side validation and deployment
remain a separate authorized step after local delivery.

## Cutover documentation

Document the secret-name mapping, package access grants, branch-protection check
names, and app release configuration. Coordinate disabling old publishing
workflows before enabling their monorepo replacements so both repositories do
not deploy concurrently. Do not remove existing deployments or archive source
repositories as part of preparing this change. Explain how maintainers now run
each project and find its pre-import history.
