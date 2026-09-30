# Depot CI

Primary automation lives in `.depot/workflows/`. It was migrated with Depot CLI
2.102.14 (`depot ci migrate workflows --yes`), then adjusted for native ARM
matrix runners, the production image E2E job's 4-CPU size, and GHCR authentication.
Existing action pins, test commands, image names, deployment destinations, release
versioning, cron schedules, and deployment concurrency groups are retained.
Docker builds still use Buildx; this migration does not switch to Depot's separate
container-build service or require a container-build project ID.

GitHub workflows now validate **fork PRs only**, using GitHub-hosted Ubuntu 24.04.
Depot currently does not support fork PR triggers. Fallback jobs are named
`Fork PR / …` so skipped GitHub jobs on same-repository PRs cannot satisfy the
normal Depot check names. They never publish images, create releases, or deploy.
Do not use `pull_request_target` to run untrusted fork code with secrets.

## Before merging (account setup and cutover)

1. Install the [Depot CLI](https://depot.dev/docs/cli/installation), run
   `depot login`, and select the intended organization. Install/authorize the
   **Depot Code Access** GitHub App for `Shroud-email/shroud.email`, including its
   requested permissions. Verify with `depot ci migrate preflight --yes`.
   CI is organization/repository-scoped; the `projectID=40gdpbrdf7` in the supplied
   CLI documentation URL is not a CI workflow configuration field.
2. Import the existing secrets with `depot ci migrate secrets-and-vars`.
   This creates a temporary migration branch and prints a push command; pushing
   it runs a GitHub workflow that transfers secret values to Depot. It is a shared
   state change and requires explicit authorization. Follow the CLI's expiry and
   cleanup instructions. Alternatively, enter values securely through Depot's
   dashboard or interactive CLI; never put them in workflow YAML or shell history.
3. Add a dedicated classic PAT as Depot secret `GHCR_TOKEN`, with `write:packages`
   (which includes `read:packages`), and set variable `GHCR_USERNAME` to the PAT
   owner's GitHub login, **not** the actor who triggered the workflow. Grant that
   account access to all three existing GHCR packages and authorize organization
   SSO if required. GitHub App `GITHUB_TOKEN` credentials cannot access Packages
   on Depot. `packages:` permissions have therefore been removed. Scope the PAT
   secret to this repository and the publishing/scanning workflows; rotate it
   according to your credential policy. Keep release-please's existing `PAT`
   separate unless its package permissions have been explicitly verified.
4. Verify the secrets below are available to the intended repository/workflows.
   Restrict production publishing credentials to trusted refs. Staging supports
   arbitrary trusted monorepo refs, so retain access for those staging runs.
   An organization owner must also enable **IPv6** in
   [Depot CI sandbox settings](https://depot.dev/orgs/_/workflows/settings/sandbox).
   Depot disables IPv6 by default. The production image binds its HTTP listener
   to the IPv6 wildcard, so image E2E fails with `:eafnosupport` without it.
   This is an organization-level setting change, not a production app change.
5. Run non-publishing Depot jobs against this working tree before cutover, for
   example `depot ci run --workflow .depot/workflows/ci.yml --job test --job image-e2e`.
   Do not add `--follow` when selecting multiple jobs: CLI 2.102.14 rejects that
   after creating the run. Follow each job separately using the returned run ID:
   `depot ci logs <run-id> --job test --follow` and
   `depot ci logs <run-id> --job image-e2e --follow`.
   Do not run all jobs in a build/deploy/release workflow as a validation shortcut:
   those jobs write to real external systems. Check artifact upload/download,
   caches, Codecov, and GitHub SARIF uploads during the first authorized runs.
6. Let in-flight GitHub publishers finish before merging. This change removes
   GitHub publishing workflows/jobs rather than enabling two publishers in
   parallel. Merge only after Depot access and secrets are ready; there is no
   automatic GitHub publishing fallback. Workflow path changes can immediately
   trigger app, website, tracker, Haraka, Caddy, and release automation on `main`.
7. Update required-check rules to accept the **Depot Code Access** check source.
   Depot retains the normal job names. Fork fallbacks have separate names; a rule
   requiring a Depot check will block fork PRs because Depot cannot emit it.
   Decide the fork-review/merge policy explicitly rather than accepting a skipped
   GitHub check as evidence of a successful Depot run. Validate same-repository
   and fork PR checks after cutover.

### Secrets and variables

All existing secret names are unchanged. The only new credential/configuration
is `GHCR_TOKEN` / `GHCR_USERNAME`:

| Workflows | Secrets |
| --- | --- |
| CI | `CODECOV_TOKEN` |
| App build/Sentry | `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `GHCR_TOKEN` |
| Caddy, hosting, scheduled Trivy image scan | `GHCR_TOKEN` |
| Release-please | `PAT` |
| Website production | `WEBSITE_BUNNY_STORAGE_PASSWORD`, `WEBSITE_BUNNY_PULLZONE_ID`, `WEBSITE_BUNNY_SCRIPT_ID`, `WEBSITE_BUNNY_DEPLOY_KEY`, `BUNNY_API_KEY` |
| Website staging | `WEBSITE_BUNNY_STAGING_STORAGE_PASSWORD`, `WEBSITE_BUNNY_STAGING_PULLZONE_ID`, `WEBSITE_BUNNY_STAGING_SCRIPT_ID`, `WEBSITE_BUNNY_STAGING_DEPLOY_KEY`, `BUNNY_API_KEY` |
| Trackers | `TRACKERS_BUNNY_STORAGE_PASSWORD`, `TRACKERS_BUNNY_PULLZONE_ID`, `BUNNY_API_KEY` |

The GHCR workflows also require `vars.GHCR_USERNAME`. Depot supplies its GitHub
App token automatically for checkout and supported GitHub API permissions; do
not import GitHub's ephemeral `GITHUB_TOKEN` as a static secret.

## Operating and validating workflows

Automatic triggers register when `.depot/workflows/` is merged to the default
branch. Inspect runs with `depot ci run list --repo Shroud-email/shroud.email`
and `depot ci status <run-id>`; use `depot ci logs` to inspect failures.
Manual workflows are dispatched through Depot, not GitHub's Actions UI.
For example, after explicitly authorizing a staging deployment:

```sh
depot ci dispatch --repo Shroud-email/shroud.email \
  --workflow website-deploy-staging.yml --ref main --input ref=your-branch
```

Local static validation from the repository root:

```sh
actionlint -config-file .github/actionlint.yaml .depot/workflows/*.yml .github/workflows/*.yml
mise exec -- zizmor --offline .depot/workflows/*.yml .github/workflows/*.yml
mise exec -- pinact run --fix=false --no-api .depot/workflows/*.yml .github/workflows/*.yml
```

Pass explicit Depot filenames to these tools: their default discovery targets
GitHub workflows. The zizmor workflows likewise pass both sets of YAML files
explicitly. The offline pin check verifies syntax, not remote tag/SHA identity.

The Elixir setup steps explicitly set `ImageOS: ubuntu24`, which setup-beam
requires to select Ubuntu OTP binaries but Depot does not supply. Their sandbox
labels are pinned to Ubuntu 24.04 to keep that metadata accurate.

References: [quickstart](https://depot.dev/docs/ci/quickstart),
[compatibility and GHCR limitation](https://depot.dev/docs/ci/compatibility),
[sandbox sizes](https://depot.dev/docs/ci/overview#depot-ci-sandboxes), and
[CLI reference](https://depot.dev/docs/cli/reference/depot-ci).
