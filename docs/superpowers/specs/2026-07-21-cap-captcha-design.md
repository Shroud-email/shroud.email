# Cap CAPTCHA Integration — Design Spec

**Date:** 2026-07-21
**Status:** Approved (pending spec review)
**Source instruction:** https://trycap.dev/prompt.md

## Goal

Add **Cap** — a self-hosted, open-source CAPTCHA (Apache 2.0) — to Shroud.email to
protect the highest-abuse-cost unauthenticated endpoints, while keeping Cap entirely
**optional**: self-hosters who set no Cap environment variables see no behavior change
(no widget, no verification HTTP call, no broken forms).

## Non-goals

- **Cap Core** (`capjs-core` npm library) is explicitly excluded. It is a JavaScript
  library meant to be imported into a JS backend; Shroud's backend is Elixir/Phoenix.
  The only realistic Core paths would be a Node sidecar (≈ Standalone minus the
  dashboard, no advantage) or a from-scratch Elixir reimplementation of the
  challenge/RSW/instrumentation protocol (substantial, drift-prone). Standalone gives
  strictly more for the same footprint. Decided during brainstorming; not revisited.
- Confirmation resend (`POST /users/confirm`) and `/api/v1/token` are not protected.
  The API token endpoint serves non-browser programmatic clients that a browser
  CAPTCHA would break; confirmation resend is lower-priority. Both can be added
  later if abuse patterns emerge. (Login was originally excluded for friction
  reasons but is now in scope per user request — see Decisions.)
- Removing the "Cap" widget label (not permitted by the integration guide).
- Migrating an existing CAPTCHA (none exists — audit confirmed).

## Decisions (locked during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Deployment mode | **Cap Standalone** | Cap Core is a JS library; doesn't fit an Elixir backend cleanly. Standalone's verify call is reCAPTCHA-shaped, trivial from Elixir. |
| Hosting | **Existing Docker host** (self-hosters' `docker-compose.yaml`) + local dev compose | User self-hosts Shroud on Docker; Cap rides alongside. |
| Compose placement | **Default `docker-compose.yaml`** in both repos (not a separate override) | User requested Cap in the default compose. Elixir app stays env-gated, so services running ≠ widget active. |
| Endpoints protected | **`POST /users/register` + `POST /users/log_in` + `POST /users/reset_password`** | Register (fake-account spam), reset_password (sends email = direct cost), and login (credential stuffing / brute force). TOTP second step, confirmation resend, and `/api/v1/token` excluded — see Non-goals. |
| Challenge protocol | **RSW time-lock + JS instrumentation** | Strongest combo. RSW (Rivest-Shamir-Wagner) is GPU-resistant sequential work; instrumentation is the browser-fingerprint second layer. |
| HTTP client | **Req** (not HTTPoison) | Req is already in `mix.lock` (transitively) and its engine Finch is a direct dep. Idiomatic mocking via `Req.Test`. |
| Gating | **Env-gated, mirroring `CHATWOOT_BASE_URL`** | Existing precedent in the codebase. Cap disabled when any of three env vars is unset. |

## Background: Cap's challenge protocols (verified from source)

Cap has **three** challenge protocols. `sha256-pow` and `rsw` are mutually exclusive
**PoW methods** (you pick one, not both — they do not run in parallel).
`instrumentation` is an additive second layer that runs alongside whichever PoW is chosen.

| Protocol | What it is | GPU-resistant |
|---|---|---|
| `sha256-pow` | Hashcash-style SHA-256 (80 challenges, difficulty 4 default) | No |
| `rsw` | Rivest-Shamir-Wagner time-lock puzzle: `y = x^(2^t) mod N`, inherently sequential | **Yes** |
| `instrumentation` | Per-request JS program run in a sandboxed iframe; verifies DOM-dependent behavior (+ optional headless-browser blocking) | n/a (different layer) |

Valid combinations: sha256-pow alone · rsw alone · sha256-pow + instrumentation ·
**rsw + instrumentation** (chosen — strongest).

Important default gotcha (from `standalone/src/server.js`): a freshly created site key
defaults to `rsw: false` **and** `instrumentation: false` (plain sha256-pow only).
The site key must be created with `instrumentation: true` and `rsw: true` explicitly.
RSW requires a one-time 2048-bit keypair generation (~700ms) at instance startup,
persisted in Valkey.

## Architecture

```
Browser                              Phoenix (Shroud.Captcha)
──────                               ──────────────────────────
form page ──→ <cap-widget>           Shroud.Captcha.enabled?/0   ← true iff all 3 env vars set
   (rendered only if enabled)            └─ Shroud.Captcha.verify(token)/1
   widget POSTs to Cap instance              └─ Req.post!("#{instance}/#{site_key}/siteverify",
   widget injects hidden cap-token               json: %{secret, response})
   into the form body                         └─ parses %{"success" => bool}; fail-closed on errors
form POST ──→ controller                plug: ShroudWeb.Plugs.VerifyCaptcha
   ↑ reads cap-token from conn.params        (no-op when Cap disabled — this is the optional gate)
   ↑ VerifyCaptcha plug runs first
   ↑ reject on missing/invalid token
   ↑ fail-closed on network/decode errors
```

### How "optional" works

Mirrors the existing `CHATWOOT_BASE_URL` pattern. Three env vars, all optional:

| Env var | Used by | When unset |
|---|---|---|
| `CAP_INSTANCE_URL` | widget + server verify | Cap disabled |
| `CAP_SITE_KEY` | widget (browser, public) | Cap disabled |
| `CAP_SECRET_KEY` | server verify only (never browser) | Cap disabled |

**Enabled** = all three set. **Disabled** = any unset.
`Shroud.Captcha.enabled?/0` centralizes the check. `VerifyCaptcha` plug short-circuits
to a no-op when disabled, so the request flow is identical to today.

## Components

### Elixir app

1. **`lib/shroud/captcha.ex`** — boundary module

   - `enabled?/0 :: boolean` — true iff all three env vars present and non-empty.
   - `verify(token) :: :ok | {:error, reason}` when `reason` is `:missing_token |
     :verification_failed | :network_error`. POSTs to
     `#{instance}/#{site_key}/siteverify` with `json: %{secret, response: token}`.
     Parses `%{"success" => true|false}` from the JSON body. Fail-closed: any Req
     exception or decode error → `{:error, :network_error}`.
   - `widget_endpoint/0 :: String.t() | nil` — `"#{instance}/#{site_key}/"` with a
     guaranteed trailing slash (Cap's #1 common failure mode). `nil` when disabled.
   - Config source: `Application.get_env(:shroud, :cap_*)` populated by `runtime.exs`.

2. **`lib/shroud_web/plugs/verify_captcha.ex`** — `@behaviour Plug`

   - `call/2`: if `Shroud.Captcha.enabled?/0` is false → return `conn` unchanged (no-op).
   - Reads `cap-token` from `conn.params`.
   - On missing token or `{:error, _}` from `verify/1`: `put_flash(:error, ...)` +
     `redirect(to: <form_get_route>)` + `halt()`. Routes:
     - register → `~p"/users/register"`
     - log_in → `~p"/users/log_in"`
     - reset_password → `~p"/users/reset_password"`
     This matches `UserResetPasswordController.create`'s existing flash+redirect
     pattern (it flashes and redirects to `/users/log_in`).
   - On `:ok` from `verify/1`: return `conn` unchanged.
   - Wired via `plug VerifyCaptcha when action in [:create]` in the three protected
     route scopes (`/users/register`, `/users/log_in`, `/users/reset_password`),
     ahead of the controller action (verify before side effects: DB write,
     session creation, confirmation/reset email send).

3. **`lib/shroud_web/components/cap.ex`** — `<.cap_widget />` function component

   - Renders `<cap-widget data-cap-api-endpoint={...}>` only when `enabled?/0`.
   - Loads the pinned widget script once: `https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.56`
     (pinned per Cap's "pin version" common-failure rule). Consistent with existing
     external CDN scripts in `root.html.heex` (Chatwoot, Better Stack, Plausible).

4. **Edits to the 3 form templates**

   - `lib/shroud_web/controllers/user_registration_html/new.html.heex`
   - `lib/shroud_web/controllers/user_session_html/new.html.heex`
   - `lib/shroud_web/controllers/user_reset_password_html/new.html.heex`

   Insert `<.cap_widget />` inside each `<.form>` before the submit button, gated on
   enabled. The widget injects its own hidden `cap-token` input into the form body,
   so no extra JS is needed for plain HTML form submission.

5. **Config & deps**

   - `mix.exs`: add `{:req, "~> 0.6"}` to deps.
   - `config/runtime.exs`: read `CAP_INSTANCE_URL`, `CAP_SITE_KEY`, `CAP_SECRET_KEY`
     via `System.get_env/1` (non-fail-fast — optional), store under
     `:shroud` app env (`:cap_instance_url`, `:cap_site_key`, `:cap_secret_key`).
   - `example.env`: append the three vars with comments explaining they're optional
     and that all three must be set to enable Cap.

### Hosting repo (`~/dev/shroud/hosting`)

6. **`docker-compose.yaml`** — add two services to the default compose:

   ```yaml
   cap:
     image: tiago2/cap:latest
     restart: unless-stopped
     depends_on:
       - valkey
     environment:
       - ADMIN_KEY=${CAP_ADMIN_KEY}
       - REDIS_URL=redis://valkey:6379
       - CORS_ORIGIN=${APP_DOMAIN}   # TODO: confirm scheme+host format in README

   valkey:
     image: valkey/valkey:9-alpine
     restart: unless-stopped
     command: valkey-server --save 60 1 --loglevel warning --maxmemory-policy noeviction
     volumes:
       - valkey_data:/data
   ```

   - `--maxmemory-policy noeviction` is a Cap hard requirement (tokens/sessions expire
     on their own TTLs; must not be evicted early).
   - Add `CAP_INSTANCE_URL=http://cap:3000`, `CAP_SITE_KEY`, `CAP_SECRET_KEY` to the
     `web` service environment (placeholders in `example.env`).
   - Add `valkey_data:` to top-level `volumes:`.
   - **`README.md`**: document (a) generating `CAP_ADMIN_KEY` (`openssl rand -hex 32`),
     (b) creating a site key with `rsw: true` + `instrumentation: true` via the
     dashboard API, (c) that Cap is opt-in at the app level — services running does not
     enable the widget until the three `CAP_*` vars are set on `web`.

### Local dev (`~/dev/shroud/shroud.email`)

7. **`docker-compose.yaml`** — add the same `cap` + `valkey` services for local
   end-to-end testing. Local `.env` gets real `CAP_*` values pointing at the local
   instance so the widget solves in dev.

### Site key creation

Once the local Cap instance is running, create the key with the locked challenge
combination (one-liner provided at implementation time):

```bash
curl -X POST http://localhost:3000/server/keys \
  -H "Authorization: Bot ${CAP_ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"name": "shroud-email", "instrumentation": true, "rsw": true}'
# → {"siteKey": "...", "secretKey": "sk-..."}  (secret shown only once)
```

Paste `siteKey` → `CAP_SITE_KEY`, `secretKey` → `CAP_SECRET_KEY` in `.env`.

## Testing (Mox-equivalent via Req.Test)

8. **`test/shroud/captcha_test.exs`** — unit tests for `verify/1`:

   - Success: mock `Req` to return `{"success": true}` → `:ok`.
   - Failure: mock returns `{"success": false}` → `{:error, :verification_failed}`.
   - Network error / Req exception → `{:error, :network_error}` (fail-closed).
   - Missing token → `{:error, :missing_token}`.
   - `enabled?/0` truthy/falsy across env-var combinations.
   Mocking via `Req.Test.expect/3`, the idiomatic Req approach (no `http_client`
   indirection, unlike the legacy `Shroud.Proxy` HTTPoison-Mox pattern).

9. **Controller tests** — extend the three existing test files:

   - `test/shroud_web/controllers/user_registration_controller_test.exs`
   - `test/shroud_web/controllers/user_session_controller_test.exs`
   - `test/shroud_web/controllers/user_reset_password_controller_test.exs`

   - When Cap env is set (test-local `Application.put_env`): a forged POST with no
     `cap-token` is rejected (Cap's Step 3 sanity check). A valid mocked token passes.
   - When Cap env is unset: existing tests pass unchanged (regression guard for the
     "optional" guarantee — disabled Cap must not break forms).

## Step 7 verification plan (local Cap instance, autonomous)

Per the integration guide's "prove it works" section — run after implementation using
the local Docker Compose Cap instance:

1. **Widget solves.** Load `/users/register`, `/users/log_in`, and
   `/users/reset_password`; widget resolves to a checkmark in ~1s. No console
   errors.
2. **Valid submission passes.** Submit the form normally; endpoint completes as before.
3. **Forged submission fails.** `curl -X POST /users/register -d '{...}'` with no
   `cap-token` → rejected.
4. **Single-use enforcement.** Capture a real token, reuse it twice → second attempt
   rejected.

All four must pass before declaring done. If headless detection (instrumentation's
`blockAutomatedBrowsers`) interferes with a headless widget-solve check, verify via a
real browser instead and note it.

## Security properties (per Cap docs)

- **Tokens are single-use.** Cap Standalone deletes the token on verification; verify
  exactly once. The plug verifies in one place.
- **Fail closed.** Network/decode errors reject the request; no fall-through to success.
- **Secret key never reaches the browser.** Only `CAP_SECRET_KEY` is used server-side;
  `CAP_SITE_KEY` is public and safe in client code.
- **`ADMIN_KEY` ≠ secret key.** Different credentials; verify uses the secret key only.

## Open items at implementation time

- Confirm the exact `CORS_ORIGIN` format Cap expects for the production compose
  (scheme+host vs host only) by reading Cap's server source, and document it.
- Generate a 32-byte `CAP_ADMIN_KEY` (`openssl rand -hex 32`) and place it in the
  local compose / hand to the user for production reuse.
