# Repository Guidelines

## Project Structure & Module Organization

Elixir application code lives in `lib/`, with context modules under `lib/shroud/` and web-facing controllers, LiveViews, and components in `lib/shroud_web/`. Configuration files are organized by environment in `config/*.exs`, while runtime assets (tailwind/esbuild bundles, images, MJML templates) live in `assets/` and `priv/static/`. Database migrations and seeds are under `priv/repo/`. Tests follow the same layout inside `test/`, with shared helpers in `test/support/` and encrypted data helpers in `lib/encrypted/`.

## Build, Test, and Development Commands

Run `mix setup` after cloning to install deps and bootstrap the database. Start the Phoenix endpoint locally with `mix phx.server` (or `iex -S mix phx.server` for interactive debugging). Use `mix ecto.reset` to drop and rebuild the schema when changing migrations. Compile and digest production assets via `mix assets.deploy`. Docker users can bring up a stack with `docker-compose up` after copying `example.env` to `.env`.

## Coding Style & Naming Conventions

Use `mix format` before committing; the project’s `.formatter.exs` enforces two-space indentation and alias/import rules. Static analysis runs with `mix credo --strict` and `mix sobelow`—treat warnings as blockers. Name modules with `PascalCase` inside the `Shroud` or `ShroudWeb` namespace, keep functions and variables in `snake_case`, and align LiveView assigns and template IDs with their component names (e.g., `AccountSettingsLive`). CSS classes should follow Tailwind utility patterns defined in `assets/tailwind.config.js`.

## Testing Guidelines

Tests are written with ExUnit; place files under `test/`, in an equivalent path to the file being tested, using the `*_test.exs` convention. Fixtured are defined in `test/support/fixtures/`. Use `mix test` to run tests. Prefer `Mox` behaviours for external services to keep tests deterministic.

## Commit & Pull Request Guidelines

Commits follow Conventional Commits (`fix:`, `feat:`, `chore:`, `ci:`) and are linted by Commitlint. Each pull request should describe the change, link the relevant issue, and call out database migrations, feature flags, or config toggles.

## Security & Configuration Tips

Never commit secrets—start by copying `example.env` and update values locally. Run `mix sobelow --config` before merging security-sensitive changes. For outbound email or third-party integrations, keep API keys in `config/runtime.exs` and reference them via `System.fetch_env!/2` so deployments fail fast when credentials are missing.
