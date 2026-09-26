# [Shroud.email](https://shroud.email/)

[![CI](https://github.com/Shroud-email/shroud.email/actions/workflows/ci.yml/badge.svg)](https://github.com/Shroud-email/shroud.email/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/Shroud-email/shroud.email/branch/main/graph/badge.svg?token=VOCBPBLSVG)](https://codecov.io/gh/Shroud-email/shroud.email)

[Shroud.email](https://shroud.email/) is an email privacy service. Protect your email address from spammers and creepy marketers
by creating unlimited aliases that remove trackers and forward messages to your regular inbox.

This repo contains our source code. If you just want to set up your email aliases, sign up for our [free 30-day trial](https://app.shroud.email/users/register).

## Contributing

Shroud is built with Elixir and [Phoenix](https://www.phoenixframework.org/). Make sure you
have Elixir and mix installed.

Our agent guidelines live in [`AGENTS.md`](AGENTS.md). If you use Claude Code, install
something like the [agents-md-loader](https://tangled.org/btao.org/claude-agents-md-loader)
so that Claude Code reads `AGENTS.md` files (it does not pick them up natively).

To start the server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Create seed data (if you want) using `mix ecto.seed`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Passkeys use the configured Phoenix endpoint URL as their WebAuthn origin and RP ID.
Set `APP_DOMAIN` to the canonical public HTTPS host in production and serve login
and Security settings on that same host. Plain HTTP works only on `localhost` in
development; passkeys enrolled on one host cannot be used on another (including
an orb portal URL). Apply database migrations before enabling passkey enrollment.

To send test emails, use e.g. [Swaks](https://www.jetmore.org/john/code/swaks/):
```
swaks --to test@example.com --server 127.0.0.1 --port 2525
```

## Libraries

- [Tailwind CSS](https://tailwindcss.com/) for styles
- [gen_smtp](https://github.com/gen-smtp/gen_smtp) for receiving emails
- [Swoosh](https://hexdocs.pm/swoosh/Swoosh.html) for sending emails

# Deploying

Set the environment variables in `example.env`.
