# [Shroud.email](https://shroud.email/)

Shroud protects your email address with aliases that remove trackers and forward
messages to your inbox. This monorepo contains the application and its supporting
projects.

| Project | Contents | Local verification |
| --- | --- | --- |
| [shroud.email](shroud.email/) | Elixir/Phoenix application | `mise exec -- mix test` |
| [website](website/) | Astro site and Bunny edge script | `mise exec -- pnpm run build` |
| [hosting](hosting/) | Self-hosting Docker Compose stack | `docker compose config --quiet` |
| [email-trackers](email-trackers/) | Tracker list and publishing script | `node --check scripts/deploy-bunny.mjs` |
| [caddy-permissive-file-storage](caddy-permissive-file-storage/) | Caddy storage module | `bash test/e2e.sh` (requires xcaddy) |

Run project commands from their respective directories. Each project keeps its
own runtime configuration and dependencies; this is not a shared npm workspace.
Install [mise](https://mise.jdx.dev/), trust the root and project `mise.toml` files,
and run `mise install` in the project you are working on.

Run `npm ci` at the root to install commitlint and Git hooks. App development
instructions are in [shroud.email/README.md](shroud.email/README.md), and agent
guidance starts in [AGENTS.md](AGENTS.md).

## Automation and development orbs

CI, releases, and deployments run on Depot CI from `.depot/workflows/`.
Deployments are separated by project; shared zizmor, commitlint, and filesystem
security checks run once. `.github/workflows/` retains validation only for fork
PRs, which Depot CI does not yet support. See [Depot CI setup and cutover](docs/depot-ci.md)
before merging workflow changes or enabling publishing.

`.agents/setup` prepares the app, website, and Go toolchains in an Amp orb.
`amp orb services ensure` starts the Phoenix preview and returns its portal URL.

See [migration and cutover notes](docs/monorepo-migration.md) before enabling
deployments from this repository. Imported history is retained through merge
commits: **do not squash the migration**.
