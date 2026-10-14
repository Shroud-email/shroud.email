# Browser extension

Run npm commands from this directory with `mise exec --`. This is an independent Vue 3/WXT project with its own lockfile.

- Read the approved spec and implementation plan under `../docs/superpowers/`.
- Inspect the approved Paper designs through Paper MCP before UI changes; compare real rendered screenshots afterward.
- Keep OAuth tokens, verifiers and authenticated networking in the background context. Runtime-validate messages from content scripts.
- Use Tailwind CSS v4 and bundled fonts/assets. No remote executable code or fonts.
- Test public outcomes using Vitest/Vue Test Utils, then real browser extension integrations. No source assertions or snapshots as substitutes.
- Run `npm test`, `npm run typecheck`, and all three `build:*` scripts before committing. Browser builds do not prove browser runtime behavior.
- Use Conventional Commits. Publishing, signing and deployment need explicit authorization.
