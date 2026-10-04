# [Shroud.email](https://shroud.email/)

Shroud protects your email address with aliases that remove trackers and forward
messages to your inbox. This monorepo contains the application and its supporting
projects.

| Project | Contents | Local verification |
| --- | --- | --- |
| [shroud.email](shroud.email/) | Elixir/Phoenix application | `mise exec -- mix test` |
| [website](website/) | Astro marketing site, Starlight docs and OpenAPI reference, and Bunny edge script | `mise exec -- pnpm run build` |
| [mobile](mobile/) | React Native/Expo app | `npx tsc --noEmit` and `npm run lint` |
| [hosting](hosting/) | Self-hosting Docker Compose stack | `docker compose config --quiet` |
| [email-trackers](email-trackers/) | Tracker list and publishing script | `node --check scripts/deploy-bunny.mjs` |
| [caddy-permissive-file-storage](caddy-permissive-file-storage/) | Caddy storage module | `bash test/e2e.sh` (requires xcaddy) |

Run project commands from their respective directories. Each project keeps its
own runtime configuration and dependencies; this is not a shared npm workspace.
Install [mise](https://mise.jdx.dev/), trust the root and project `mise.toml` files,
and run `mise install` in the project you are working on.

Run `mise exec -- npm ci` at the root to install Prettier, commitlint, and the
root Lefthook Git hooks. Lefthook is pinned in `mise.toml`. The pre-commit hook
formats staged JavaScript, TypeScript, Elixir, and HEEx files and stages the
formatted changes while preserving unstaged edits. It also checks Phoenix
formatting and runs Credo.

Run `npm run format` at the root to format JavaScript and TypeScript across all
projects, or `npm run format:check` to check them without changing files.
Generated files and dependencies are excluded in `.prettierignore`.
Run `mise exec -- mix format` from `shroud.email/` to format Elixir and HEEx.
CI checks both formatters.

App development instructions are in [shroud.email/README.md](shroud.email/README.md),
and agent guidance starts in [AGENTS.md](AGENTS.md).

## Automation and development orbs

All GitHub Actions live in `.github/workflows/`. Deployments are separated by
project; shared zizmor, commitlint, and filesystem security checks run once.

`.agents/setup` prepares the app, website, and Go toolchains in an Amp orb.
`amp orb services ensure` starts the Phoenix preview and returns its portal URL.

### CI repair trigger

`.github/workflows/amp-ci-repair.yml` watches all workflows with a `**` wildcard.
Any workflow failure on `main`, including manual and scheduled runs, starts a
fresh repair orb that investigates all failed jobs in that run attempt. There is
no workflow-name allowlist or PR trigger. Pull request runs, successful runs,
cancellations, and the repair workflow itself do not launch repair agents.

GitHub Actions launches the orb with `amp -ox` and records its link in the job
summary. No listener thread needs to remain unarchived. The agent must verify a
safe fix before pushing a repair branch and opening a PR. It must not merge,
deploy, push to `main`, or change production data or shared infrastructure.

To enable the trigger:

1. Add an Amp access token from [Amp Security Settings](https://ampcode.com/settings/security)
   as the repository Actions secret `AMP_API_KEY`. Use an access token, not a
   short-lived CLI login session token. Never paste the token into a thread.
2. Ensure the token's owner can access the Amp project `taobojlen/shroud.email`
   and has connected GitHub in Amp with access to logs, branches, and PRs.
3. Merge the workflow into `main`. GitHub only activates `workflow_run` listeners
   from the default branch.

The privileged launcher checks out trusted `main` code, not the failed run's
commit, and does not consume upstream artifacts or caches. Its GitHub token has
read-only contents permission. The Amp token is only supplied to the launch step.

Rerunning the launcher does not create another orb. If launching fails, inspect
Amp first: the orb can exist even when its creation response is lost. A new
failed attempt of the source workflow can launch a new repair thread.

See [migration and cutover notes](docs/monorepo-migration.md) before enabling
deployments from this repository. Imported history is retained through merge
commits: **do not squash the migration**.
