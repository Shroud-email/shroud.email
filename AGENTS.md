# Repository Guidelines

## Project Overview

Shroud.email is an email privacy service built with Elixir/Phoenix. It allows users to create unlimited email aliases that remove trackers and forward messages to their regular inbox.

## Project Structure & Module Organization

Elixir application code lives in `lib/`, with context modules under `lib/shroud/` and web-facing controllers, LiveViews, and components in `lib/shroud_web/`. Configuration files are organized by environment in `config/*.exs`, while runtime assets (tailwind/esbuild bundles, images, MJML templates) live in `assets/` and `priv/static/`. Database migrations and seeds are under `priv/repo/`. Tests follow the same layout inside `test/`, with shared helpers in `test/support/` and encrypted data helpers in `lib/encrypted/`.

## Architecture

### Context Modules (`lib/shroud/`)
Business logic organized into bounded contexts:
- **Accounts** - User management, authentication, TOTP 2FA
- **Aliases** - Email alias creation and management
- **Billing** - Stripe payments, subscription management
- **Domain** - Custom domain management, DNS verification
- **Email** - SMTP server, email processing, spam detection, tracker removal

### Web Layer (`lib/shroud_web/`)
Phoenix web layer with LiveView for interactive pages:
- Controllers in `controllers/`
- LiveView pages in `live/` (main dashboard, alias details, domains, detention)
- Reusable components in `components/`
- Routes defined in `router.ex`

### Email Processing Pipeline
```
SMTP Input → ParsedEmail → Tracker Removal → Spam Check → Forward
```
- SMTP server runs on port 2525 (dev) using gen_smtp
- Tracker pixels and UTM params removed via Floki
- Spam detection using SpamAssassin headers
- Outgoing email sent via Swoosh

### Background Jobs (Oban)
Queues: `default`, `outgoing_email`, `dns_checker`, `notifier`

Scheduled tasks via Quantum:
- Daily: tracker list updates, trial expiration emails
- Hourly: spam cleanup, domain verification

### Data Encryption
Cloak Ecto vault (`lib/shroud/vault.ex`) encrypts sensitive user data at rest.

## Common Commands

```bash
# Setup (install deps + create/migrate database)
mix setup

# Start development server
mix phx.server
iex -S mix phx.server    # with interactive REPL

# Database
mix ecto.reset           # drop and rebuild database
mix ecto.migrate         # run pending migrations
mix ecto.seed            # seed with sample data

# Testing
mix test                 # run all tests
mix test path/to/test.exs:42  # run single test at line

# Code quality (run before committing)
mix format               # format code
mix credo --strict       # linting
mix sobelow              # security scanning
mix compile --warnings-as-errors

# Assets
mix assets.deploy        # build and digest for production

# Docker
docker-compose up        # start development environment
```

## Coding Style & Naming Conventions

- 2-space indentation (enforced by `.formatter.exs`)
- PascalCase for modules inside the `Shroud` or `ShroudWeb` namespace
- snake_case for functions and variables
- Align LiveView assigns and template IDs with their component names (e.g., `AccountSettingsLive`)
- CSS classes should follow Tailwind utility patterns defined in `assets/tailwind.config.js`
- Run `mix format` before committing
- Static analysis runs with `mix credo --strict` and `mix sobelow`—treat warnings as blockers

## Testing Guidelines

- Tests are written with ExUnit; place files under `test/`, in an equivalent path to the file being tested
- Test files use `*_test.exs` naming convention
- Fixtures defined in `test/support/fixtures/`
- Use `mix test` to run tests
- Prefer `Mox` behaviours for external services to keep tests deterministic (defined in `test/test_helper.exs`)

## Commit & Pull Request Guidelines

Commits follow Conventional Commits (`fix:`, `feat:`, `chore:`, `ci:`) and are linted by Commitlint. Each pull request should describe the change, link the relevant issue, and call out database migrations, feature flags, or config toggles.

## Security & Configuration

- Never commit secrets—start by copying `example.env` to `.env` and update values locally
- Run `mix sobelow --config` before merging security-sensitive changes
- Environment variables loaded via `config/runtime.exs` using `System.fetch_env!/2` (fail-fast)
- For outbound email or third-party integrations, keep API keys in `config/runtime.exs`
