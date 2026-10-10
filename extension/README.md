# Shroud.email browser extension

Vue 3, TypeScript and WXT build a shared Manifest V3 extension for desktop Chrome, Firefox and Safari.

Use the project-local Node version: `mise exec -- npm ci`. Run `mise exec -- npm run dev` for development.
Run `mise exec -- npm test` and `mise exec -- npm run typecheck` for unit tests and TypeScript checks.
Build each target with `mise exec -- npm run build:chrome`, `build:firefox`, or `build:safari`.
Load `.output/chrome-mv3/` as an unpacked extension in Chrome, or `.output/firefox-mv3/manifest.json` as a temporary Firefox add-on.

The approved specification and implementation plan live under `../docs/superpowers/`. Paper MCP supplies the UI designs.
OAuth uses a dedicated public PKCE client on the selected Phoenix instance. Website access is optional, separate from instance access.
Build success does not establish browser runtime compatibility. Safari packaging, integration verification and publishing are separate steps.

The default instance is `https://app.shroud.email`. The small Server URL disclosure on the sign-in screen accepts a self-hosted HTTPS instance. HTTP is restricted to loopback development. The instance must include the extension OAuth-client migration, `/oauth/extension/callback`, and the alias capabilities/domain APIs from this repository. Apply its migrations through your normal deployment process before using the extension.

Enable the email-field icon in Settings after granting website access. Without that permission the popup still works. Removing website permission removes injected icons and menus. Tokens and authenticated requests stay in the background context; website scripts never receive credentials. Creation does not retry an ambiguous failed POST. The UI asks you to check the alias list instead.

For Safari, build the Safari target first, then run `mise exec -- npm run package:safari` on macOS with Xcode. This regenerates the disposable, ignored `safari/Shroud.email/` project, overwriting changes inside that generated directory. Open its Xcode project to configure signing and install it. Enable the extension in Safari Settings. For an unsigned local build:

```sh
xcodebuild -project safari/Shroud.email/Shroud.email.xcodeproj \
  -scheme Shroud.email -configuration Debug \
  -derivedDataPath ../.amp/in/safari-build CODE_SIGNING_ALLOWED=NO build
```

Real Chromium integration tests require Playwright Chromium and a disposable local PostgreSQL database. From `shroud.email/`, create and migrate the dedicated database:

```sh
MIX_ENV=test POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=55437 POSTGRES_DB=shroud_extension_e2e mise exec -- mix ecto.create
MIX_ENV=test POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=55437 POSTGRES_DB=shroud_extension_e2e mise exec -- mix ecto.migrate
MIX_ENV=test mise exec -- mix assets.deploy
MIX_ENV=test POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=55437 POSTGRES_DB=shroud_extension_e2e EXTENSION_E2E=1 mise exec -- mix run --no-start --no-halt priv/repo/extension_e2e_seeds.exs
```

The seed script refuses any environment except the exact loopback `shroud_extension_e2e` test database. It starts Phoenix on port 4407. Tests reset only their disposable fixture accounts. From `extension/`, run:

```sh
mise exec -- npx playwright install chromium
mise exec -- npm run build:chrome
mise exec -- npm run test:e2e
```

Use `EXTENSION_E2E_DB_PORT` if PostgreSQL uses a different port. Chromium tests exercise real OAuth, API calls, clipboard, background restart, account search/pagination, custom-domain filling, alias limits, permission removal, iframe/dynamic fields and replacement during creation. Headless tests preauthorize host grants through Chromium's developer API, then exercise the extension's real permission requests; they do not test the native permission prompt.

Verification covers Chrome/Firefox/Safari production builds, Chromium journeys, Firefox temporary installation, and an unsigned native Safari build. Full Firefox and Safari OAuth/fill journeys require separate browser verification. Signing, store submission and publishing are not part of these commands. Firefox declares account/authentication data categories because the extension processes email addresses and OAuth credentials; it includes no telemetry.
