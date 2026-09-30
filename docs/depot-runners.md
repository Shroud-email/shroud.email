# Depot GitHub Actions runners

GitHub Actions remains the CI engine. All workflows live in `.github/workflows/`;
Depot supplies ephemeral runners, not Depot CI. There is one set of workflows for
same-repository and fork pull requests, with the existing triggers, check names,
permissions, action pins, image names, and deployment destinations unchanged.

## Setup

1. An organization owner must connect `Shroud-email` in Depot's **GitHub Actions**
   section and install/authorize the Depot GitHub App for this repository. This
   is separate from the Depot CI Code Access integration.
2. In GitHub organization **Settings → Actions → Runner groups**, allow the
   runner group to access this repository and enable **Allow public repositories**.
   Retain GitHub's approval requirements for external contributors. Depot runners
   are ephemeral, but fork code is still untrusted: do not expose secrets or use
   `pull_request_target` to execute it with a privileged token.
3. Push the runner-label changes and inspect the PR runs in GitHub Actions.
   Verify tests, production-image E2E, caches, artifacts, and SARIF uploads there.
   Verify a fork PR separately, including contributor approval and runner-group
   access. Publishing/release/deployment jobs retain their existing trusted
   triggers; do not manually dispatch them just to test runner setup.

## Runner selection

| Jobs | Label |
| --- | --- |
| Default jobs | `depot-ubuntu-24.04` (2 CPUs) |
| App amd64 image build and production-image E2E | `depot-ubuntu-24.04-4` (4 CPUs) |
| App arm64 image build | `depot-ubuntu-24.04-arm-4` (4 CPUs, native ARM) |

These runners use GitHub's standard runner images. Docker builds still use the
existing Buildx actions and GitHub cache backend; no Depot container-build
project is required.

## Credentials and checks

Secrets stay in GitHub. GHCR continues using GitHub's ephemeral `GITHUB_TOKEN`
with `packages` permissions; **no new GHCR PAT or `GHCR_USERNAME` is required**.
The existing release-please `PAT` is unchanged. Sobelow and Trivy use the standard
CodeQL SARIF upload action in a real GitHub Actions run; no custom uploader is
needed. GitHub supports code-scanning uploads on `pull_request` runs with
read-only fork tokens.

Check names and their GitHub Actions source are unchanged. If required-check
rules were already switched to Depot Code Access for the abandoned Depot CI
migration, restore them to GitHub Actions. Stop using `depot ci run` to validate
these workflows; view runs in GitHub's Actions UI or with `gh run list` and
`gh run view <run-id> --log-failed`.

Previously copied Depot CI secrets and its Code Access app are not used by this
configuration. An owner can remove unused credentials/integrations after checking
that no other repositories depend on them; do not remove the runners integration
or the existing release-please token.

## Local workflow validation

From the repository root:

```sh
mise install
mise exec -- actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml
mise exec -- zizmor --offline .github/workflows/*.yml
mise exec -- pinact run --fix=false --no-api .github/workflows/*.yml
```

The offline pin check verifies syntax, not remote tag/SHA identity.

References: [runner quickstart](https://depot.dev/docs/github-actions/quickstart),
[runner types](https://depot.dev/docs/github-actions/runner-types), and
[GitHub code-scanning permission exception](https://docs.github.com/en/code-security/code-scanning/troubleshooting-code-scanning/resource-not-accessible).
