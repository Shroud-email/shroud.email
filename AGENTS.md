# Shroud.email monorepo

- `shroud.email/`: Phoenix application. Read its `AGENTS.md`; run Mix, assets, and app E2E commands from that directory.
- `website/`: Astro marketing/docs site and Deno edge script. Read its `AGENTS.md`; use its pnpm lockfile and project-local mise toolchain.
- `hosting/`: self-hosting Compose stack. Run Compose from here; Caddy's build context includes the sibling Go module.
- `email-trackers/`: tracker list and Bunny publishing script.
- `caddy-permissive-file-storage/`: Go module. Run `bash test/e2e.sh` here with xcaddy installed.
- Root npm dependencies are for Git hooks/commitlint, not a shared JavaScript workspace. Root mise pins shared maintenance tools; project mise files pin runtimes.
- All active GitHub Actions belong in root `.github/workflows/`. Action inputs are root-relative even when shell steps have a project working directory.
- Preserve existing image names and deployment destinations. See `docs/monorepo-migration.md` for history and cutover requirements.
- Use Conventional Commits. Never fill in a PR body; leave it empty for the user.
- Preserve imported merge history when integrating the migration; do not squash it.
