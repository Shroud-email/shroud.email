# Shroud.email browser extension

Vue 3, TypeScript and WXT build a shared Manifest V3 extension for desktop Chrome, Firefox and Safari.

Use the project-local Node version: `mise exec -- npm ci`. Run `mise exec -- npm run dev` for development.
Run `mise exec -- npm test` and `mise exec -- npm run typecheck` for unit tests and TypeScript checks.
Build each target with `mise exec -- npm run build:chrome`, `build:firefox`, or `build:safari`.
Load `.output/chrome-mv3/` as an unpacked extension in Chrome, or `.output/firefox-mv3/manifest.json` as a temporary Firefox add-on.

The approved specification and implementation plan live under `../docs/superpowers/`. Paper MCP supplies the UI designs.
OAuth uses a dedicated public PKCE client on the selected Phoenix instance. Website access is optional, separate from instance access.
Build success does not establish browser runtime compatibility. Safari packaging, integration verification and publishing are separate steps.
