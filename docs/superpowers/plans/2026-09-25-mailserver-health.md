# Mailserver Health Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give admins on-demand, read-only mailserver configuration diagnostics.

**Architecture:** A checker in `Shroud.Email` reads configured domain and SMTP settings, resolves DNS, probes SMTP endpoints with bounded network calls, and returns independent result rows. An admin LiveView starts it asynchronously and renders the rows and refresh state. Only the admin router/session exposes the page.

**Tech Stack:** Elixir/OTP DNS, TCP and SSL, Phoenix LiveView, ExUnit, Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-09-25-mailserver-health-design.md`

## Global Constraints

- No mail sent, AUTH credentials transmitted, user-supplied network target, periodic job, new dependency, or hosting-repository change.
- Do not claim proof of external reachability, downstream delivery, outbound IP/SPF alignment, or DKIM signatures.
- Use `EMAIL_DOMAIN`, existing configured inbound SMTP port and `Shroud.Mailer` relay options.
- Limit MX targets and bound DNS, socket and TLS operations; surface partial failures independently.

---

### Task 1: DNS diagnostics

**Files:**
- Create: `lib/shroud/email/mailserver_health.ex` (owns diagnostics and result contract)
- Create: `test/shroud/email/mailserver_health_test.exs`

**Interfaces:**
- Produces: `Shroud.Email.MailserverHealth.run/0 :: %{checked_at: DateTime.t(), results: [map()]}`; each result has `:name`, `:status` (`:pass | :fail | :unknown`), `:detail`. SMTP tasks consume resolved MX targets internally.

- [ ] Write tests using a fake DNS client for asymmetric MX targets, missing MX, resolver failure, valid and malformed SPF/DKIM/DMARC records. Assert actual statuses/details, not just row counts.
- [ ] Run `mise exec -- mix test test/shroud/email/mailserver_health_test.exs` and observe failures before implementing.
- [ ] Implement bounded MX/A/AAAA and TXT lookups with DNS error distinction, one row per target and policy, and non-ambiguous result text. Avoid treating split TXT chunks as multiple records.
- [ ] Run focused tests and `mise exec -- mix format` on touched files. Commit `feat: add mailserver DNS diagnostics`.

### Task 2: SMTP, TLS, and private pipeline

**Files:**
- Modify: `lib/shroud/email/mailserver_health.ex`
- Modify: `test/shroud/email/mailserver_health_test.exs`

**Interfaces:**
- Extends `run/0` results with per-MX port 25 greeting/EHLO/STARTTLS/certificate rows; configured relay and local listener rows. Keeps every check independent even when another fails.

- [ ] Write tests with controlled local SMTP servers or injected probe functions for truncated/bad greeting, EHLO without STARTTLS, TCP timeout, TLS handshake failure, wrong hostname, and valid certificate. Include a case with one healthy MX and one failed MX, and local listener/relay failure isolation.
- [ ] Run focused tests to confirm failures before implementation.
- [ ] Implement bounded TCP greeting and multiline EHLO parser, STARTTLS negotiation, `:ssl` peer and hostname verification with CA trust, a relay probe compatible with configured TLS mode, and a local listener greeting probe. Close sockets in all paths; never issue message or AUTH commands.
- [ ] Run focused tests and format touched files. Commit `feat: probe SMTP and TLS health`.

### Task 3: Admin UI and access

**Files:**
- Create: `lib/shroud_web/live/mailserver_health_live/index.ex`
- Modify: `lib/shroud_web/router.ex`
- Modify: `lib/shroud_web/components/layouts/navbar.html.heex`
- Create: `test/shroud_web/live/mailserver_health_live_test.exs`

**Interfaces:**
- LiveView consumes `Shroud.Email.MailserverHealth.run/0` and renders timestamp, results and refresh control. Existing `require_admin_user` and `AdminUserLiveAuth` enforce access.

- [ ] Write LiveView tests asserting admin-only route, loading/result states, refresh, and that non-admin requests are rejected. Inject deterministic checker results for tests.
- [ ] Run tests to confirm failure before implementation.
- [ ] Add route inside admin live session, desktop/mobile nav links, and LiveView using async task handling; avoid synchronous network calls in mount/events. Add IDs to key elements and label diagnostic limitations.
- [ ] Run focused LiveView tests, format touched files, compile with warnings as errors and lint. Commit `feat: show admin mailserver health diagnostics`.

### Task 4: Integrated verification

**Files:** no additional feature files unless a check reveals a defect.

- [ ] Run focused tests, wider email/web tests, `mix format --check-formatted`, `mix credo --strict`, and `mix compile --warnings-as-errors` via `mise exec --`; report unrelated baseline failures separately.
- [ ] Start the configured dev service and inspect the rendered admin page and representative loading/failure states via browser screenshots and `view_media`. Verify the admin route's DOM and interactions, not merely presence of screenshots.
- [ ] Inspect diff for target/credential leakage, blocking work, misleading pass states, and unbounded resource use; fix issues and rerun affected checks.
