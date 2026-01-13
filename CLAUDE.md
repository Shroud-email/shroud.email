# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shroud.email is an email privacy service built with Elixir/Phoenix. It allows users to create unlimited email aliases that remove trackers and forward messages to their regular inbox.

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

## Testing

- Tests in `test/` mirror `lib/` structure
- Fixtures in `test/support/fixtures/`
- Use Mox behaviors for external services (defined in `test/test_helper.exs`)
- Test files use `*_test.exs` naming convention

## Code Style

- 2-space indentation (enforced by `.formatter.exs`)
- PascalCase for modules, snake_case for functions/variables
- Run `mix format` before committing
- Treat credo and sobelow warnings as blockers

## Commit Convention

Follow Conventional Commits: `fix:`, `feat:`, `chore:`, `ci:`

## Configuration

Environment variables loaded via `config/runtime.exs` using `System.fetch_env!/2` (fail-fast).
Copy `example.env` to `.env` for local development. Never commit secrets.
