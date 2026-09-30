# Shroud.email monorepo

- `shroud.email/`: Phoenix application. Read its `AGENTS.md`; run Mix, assets, and app E2E commands from that directory.
- `website/`: Astro marketing/docs site and Deno edge script. Read its `AGENTS.md`; use its pnpm lockfile and project-local mise toolchain.
- `hosting/`: self-hosting Compose stack. Run Compose from here; Caddy's build context includes the sibling Go module.
- `email-trackers/`: tracker list and Bunny publishing script.
- `caddy-permissive-file-storage/`: Go module. Run `bash test/e2e.sh` here with xcaddy installed.
- Root npm dependencies are for Git hooks/commitlint, not a shared JavaScript workspace. Root mise pins shared maintenance tools; project mise files pin runtimes.
- Primary CI, releases, and deployments belong in root `.depot/workflows/`. Root `.github/workflows/` contains only fork-PR validation until Depot supports forks. Never add a second publisher there. Action inputs are root-relative even when shell steps have a project working directory. See `docs/depot-ci.md` for setup and validation commands.
- Preserve existing image names and deployment destinations. See `docs/monorepo-migration.md` for history and cutover requirements.
- Use Conventional Commits. Never fill in a PR body; leave it empty for the user.
- Preserve imported merge history when integrating the migration; do not squash it.
