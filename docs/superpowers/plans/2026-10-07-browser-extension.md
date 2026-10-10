# Browser extension implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the user chooses delegation. Steps use checkbox syntax for tracking.

**Goal:** Deliver a locally verified Vue browser extension for OAuth login, alias creation/copying, and optional email-field filling.

**Architecture:** Phoenix remains the authority for OAuth, alias limits, and usable domains. A WXT background context owns credentials and API calls; Vue renders the popup and isolated content-script menu. Chrome, Firefox, and desktop Safari share application code and tab-based PKCE authorization.

**Tech Stack:** Vue 3, TypeScript, WXT, Tailwind CSS v4, Vitest, Vue Test Utils, Playwright; Elixir/Phoenix, ExUnit, OpenApiSpex.

**Spec:** [Approved specification](../specs/2026-10-07-browser-extension-design.md). Read it before this plan; its requirements apply to every task.

## Global constraints

- Synchronize unpublished work with current `origin/main` and read root/scoped `AGENTS.md` before execution. Preserve unrelated edits and imported history. Use an isolated worktree through the using-git-worktrees skill at execution time.
- Use WXT, TypeScript, Vue 3, and Tailwind CSS v4. Explicit Manifest V3 for Chrome, Firefox, and Safari. Own `extension/package-lock.json`; no root application dependencies.
- Paper is the UI source of truth. Access file `01M3VEVRW9WWCGNZH64T87G0SP`, page `p-2-0`, through Paper MCP before UI implementation. Inspect trees, computed styles, and screenshots. Report unavailable tools or missing designs rather than inventing a replacement.
- Default instance `https://app.shroud.email`. HTTPS origins plus loopback HTTP development only. No passwords, mobile client ID, OAuth redirect wildcards, or expanded dynamic MCP registration.
- OAuth scopes: `profile:read aliases:read aliases:create domains:read`. Exact issuer-owned `/oauth/extension/callback`; tab-based authorization on every browser.
- Tokens stay in trusted extension contexts, local storage only. No arbitrary network requests exposed through messages. POST creation is never automatically retried after uncertain transport failure.
- Product name **Shroud.email**, bundled Inter and actual SVG logo, six-pixel controls, Phoenix indigo/slate roles. No header logo, Open Shroud.email, Website access row, separate copied screen, or Use an existing alias error action.
- Optional website permission remains separate from API-instance permission; icon toggle defaults off. Missing permission gets only Allow website access.
- Test outcomes, not implementation/source text. ExUnit fixtures and Mox for backend external services; DOM assertions for components; real Chromium integration in addition to mocked unit boundaries.
- Review screenshots for every affected state. Store artifacts under `.amp/in/artifacts/` with repository-local `/.amp/in/` exclusion. Never capture credentials.
- Local commits only. Production migrations, publishing, deployment, signing, pushing, and PR creation require separate authorization. Never fill a PR body.

## Review focus

1. A delayed API result after Logout or switching instance must not restore the previous account's data or credentials (Tasks 4–5).
2. A slow search response must not replace results for a newer query, including an empty query (Task 6).
3. Permission revoked in browser settings must remove website injection without breaking toolbar API access (Tasks 5 and 7).
4. A framework replaces the selected input during creation: retain the alias and offer Copy, without filling a different input (Task 7).
5. A saved custom domain loses verification: use the current default on next entry; a stale in-flight request must fail server-side (Tasks 2 and 5).

## File ownership and shared contracts

Backend edits stay in existing OAuth/alias contexts and controllers. New callback templates, capability controller, and migration have narrow responsibilities. Extension files are grouped by background, popup, and content ownership; share types and branding, not a new cross-project SDK.

Proposed extension structure:

```text
extension/
  package.json, package-lock.json, mise.toml, tsconfig.json, wxt.config.ts
  vitest.config.ts, playwright.config.ts, AGENTS.md, README.md
  entrypoints/background.ts
  entrypoints/popup/index.html, main.ts, App.vue
  entrypoints/email-fields.content.ts
  background/auth.ts, api.ts, messages.ts, preferences.ts
  shared/contracts.ts, instance.ts
  popup/Login.vue, AliasList.vue, CreateAlias.vue, Settings.vue
  popup/useAccount.ts
  content/fields.ts, InlineMenu.vue
  assets/theme.css, logo.svg
  public/fonts/Inter.var.woff2
  tests/unit/*.test.ts
  tests/e2e/extension.spec.ts, fixtures.ts, website.html
  scripts/package-safari.sh
```

Wire responses keep existing fields; never add OAuth secrets to `AccountView`:

```ts
export type Alias = {
  address: string; enabled: boolean; title: string | null; notes: string | null;
  forwarded: number; blocked: number; blocked_addresses: string[];
};
export type AliasPage = {
  email_aliases: Alias[]; page_number: number; page_size: number;
  total_entries: number; total_pages: number;
};
export type Capabilities = {
  alias_count: number; alias_limit: number | null; can_create: boolean;
  default_domain: string;
};
export type CreateAlias = { title?: string; domain?: string; local_part?: string };
export type Appearance = 'system' | 'light' | 'dark';
export type Preferences = {
  appearance: Appearance; showIcon: boolean; selectedDomain: string;
};
export type AccountView = {
  instance: string; email: string; capabilities: Capabilities;
  domains: string[]; preferences: Preferences; websitePermission: boolean;
};
export type Failure = {
  kind: 'auth' | 'limit' | 'validation' | 'network' | 'permission' | 'unknown';
  message: string; creationUncertain?: boolean;
};
export type Reply<T> = { ok: true; value: T } | { ok: false; error: Failure };
export type Message =
  | { type: 'account' }
  | { type: 'aliases'; search: string; page: number; recent?: boolean }
  | { type: 'create'; input: CreateAlias }
  | { type: 'login'; instance: string }
  | { type: 'logout' }
  | { type: 'preferences'; patch: Partial<Preferences> }
  | { type: 'open'; destination: 'signup' | 'billing'; instance?: string };
```

`account` returns `Reply<AccountView | null>`, `aliases` returns `Reply<AliasPage>`, `create` returns `Reply<Alias>`, remaining messages return `Reply<void>`. Validate messages at runtime as well as compile time. `recent` maps to `enabled=true`, first page, page size three; ordinary aliases use server pagination. Domain wire objects are normalized to strings inside the API boundary.

## Task 1: Official extension OAuth client and safe callback

**Files:** Modify `shroud.email/lib/shroud/oauth.ex`, `lib/shroud/oauth/clients.ex`, `lib/shroud_web/controllers/oauth_controller.ex`, `lib/shroud_web/controllers/oauth_html.ex`, `lib/shroud_web/router.ex`. Create `lib/shroud_web/controllers/oauth_html/extension_callback.html.heex`. Generate migration with `mix ecto.gen.migration register_extension_oauth_client`. Extend `test/shroud_web/controllers/oauth_api_test.exs` and `test/shroud/oauth_test.exs`. Backend paths after the first are relative to `shroud.email/`.

**Interfaces:** Dedicated public client UUID generated once during implementation and copied into `extension/background/auth.ts`; resource `/api/v1`; callback `OAuth.issuer() <> "/oauth/extension/callback"`. API scope ceiling is exactly the four specified scopes. Existing mobile/MCP clients retain their contracts.

- [ ] Write consent/code-exchange tests for the dedicated client, S256, exact issuer callback, four allowed scopes, and rejection of `aliases:delete`, foreign callback and missing PKCE. Use existing `authorization_params/2`, then replace client/resource/redirect fields as `oauth_api_test.exs` does. Include callback security headers and DOM checks:

```elixir
conn = build_conn() |> get("/oauth/extension/callback")
assert get_resp_header(conn, "cache-control") == ["no-store"]
assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
assert conn |> html_response(200) |> Floki.parse_document!()
       |> Floki.find("#extension-oauth-callback") |> length() == 1
```

- [ ] Run `mise exec -- mix test test/shroud_web/controllers/oauth_api_test.exs test/shroud/oauth_test.exs` from `shroud.email/`. Confirm new cases fail for missing registration/route/policy, not fixture errors.
- [ ] Generate the migration. Follow official public-client TTLs and metadata. For this dedicated client only, resolve redirects from the canonical issuer in both `Clients.metadata/1` and Boruta's `Clients.get_client/1`; never accept caller-provided issuer/redirect values. This allows self-hosted instances without wildcard redirects or runtime DB writes. Enforce its scope ceiling in authorization validation. Verify custom endpoint configuration in a non-async test, restoring application configuration afterward.
- [ ] Render a minimal callback page without application layout, analytics, or third-party assets. Set no-store/no-referrer. Background code will consume the callback URL and navigate its own auth tab to the clean callback URL before closing; page does not race to erase the query itself. Serve no credential-dependent content. No inline scripts.
- [ ] Run the targeted suite plus OAuth regression/concurrency tests. Run format, compile, Credo and Sobelow from `shroud.email/`. Commit only these files: `feat: support extension OAuth authorization`.

## Task 2: Authoritative alias capabilities and selected-domain creation

**Files:** Modify `shroud.email/lib/shroud/aliases.ex`, `lib/shroud_web/controllers/api/v1/email_alias_controller.ex`, `schemas.ex`, `lib/shroud_web/router.ex`; create `controllers/api/v1/alias_capabilities_controller.ex`. Extend `test/shroud/aliases_test.exs`, `test/shroud_web/controllers/api/v1/email_alias_controller_test.exs`, `test/shroud_web/controllers/oauth_api_test.exs`, `test/shroud_web/api_spec_test.exs`.

**Interfaces:** `GET /api/v1/alias-capabilities` requires `aliases:read`, returns `Capabilities`. Add `Aliases.creation_capabilities(user)` as policy source, reuse it for creation eligibility. Extend POST `/aliases`: no fields = existing random shared; domain-only = random selected domain; both strings = explicit local name on allowed domain. Error `%{error: existing_message, code: "free_limit_reached"}` for limit; preserve other error contracts. `/me` stays unchanged.

- [ ] Write cases with four/five/six nondeleted aliases, one disabled counted, one deleted excluded, another user's aliases excluded, active paid unlimited, inactive cannot create. Independently assert count/limit/can_create. Use confirmed users and existing fixtures. Pin boundary behavior:

```elixir
assert %{alias_count: 5, alias_limit: 5, can_create: false} =
         Shroud.Aliases.creation_capabilities(free_user)
assert %{alias_limit: nil, can_create: true} =
         Shroud.Aliases.creation_capabilities(paid_user)
```

- [ ] Test domain-only creation returns an address on a currently verified owned custom domain with matching `domain_id`; foreign, recently invalidated, unknown, and stale verification fail without insertion. Test default shared domain selection and explicit custom names, invalid partial fields, preservation of existing requests and stable free-limit code. Use domain fixtures; don't call DNS in tests. Test capability endpoint rejects missing scope, while preserving API-token compatibility.
- [ ] Run targeted ExUnit tests and confirm failures reflect absent behavior.
- [ ] Implement one policy source using `Accounts.active?/1`, `Aliases.count_aliases/1`, `free_alias_limit/0` and current free status. Reuse `Aliases.generate_alias_name/1` and `Util.email_domain/0`. Validate selected custom domain ownership and all verification timestamps server-side. Do not extend permissions or trust domain IDs supplied by clients. Add OpenAPI operation/schema and no-store headers.
- [ ] Rerun targeted tests and existing aliases/domain/OpenAPI tests, then backend quality commands. Commit: `feat: expose alias creation capabilities and domain selection`.

## Task 3: Extension project and validated instance contract

**Files:** Create `extension/package.json`, lockfile, `mise.toml`, `tsconfig.json`, `wxt.config.ts`, `vitest.config.ts`, `AGENTS.md`, `shared/contracts.ts`, `shared/instance.ts`, `tests/unit/instance.test.ts`, `entrypoints/background.ts`, popup index/main/App, and `README.md`. Modify root `.gitignore` only for extension-generated outputs.

**Interfaces:** `normalizeInstance(input: string): string` returns a canonical origin or throws validation error. WXT entrypoints compile for all three MV3 targets. Scripts: `dev`, `test`, `typecheck`, `build:chrome`, `build:firefox`, `build:safari`, `test:e2e`, `package:safari`.

- [ ] Install compatible stable WXT/Vue tooling locally with an independent lockfile. Use Vue module, `vue-tsc`, Vitest, Vue Test Utils, jsdom, Tailwind v4/Vite plugin, and Playwright. Pin the Node runtime in local mise from a supported installed version. Do not install a root workspace or React.
- [ ] Write instance tests before implementation:

```ts
expect(normalizeInstance(' https://mail.example:8443/ ')).toBe('https://mail.example:8443');
expect(normalizeInstance('http://127.0.0.1:4000')).toBe('http://127.0.0.1:4000');
for (const bad of ['http://mail.example', 'https://u:p@mail.example',
  'https://mail.example/path', 'https://mail.example?x=1',
  'https://mail.example#x', 'https://localhost.evil.example/path']) {
  expect(() => normalizeInstance(bad)).toThrow();
}
```

- [ ] Run `mise exec -- npm test -- tests/unit/instance.test.ts` from `extension/`; confirm red.
- [ ] Implement normalization with URL parsing, rejecting credentials, non-root paths, queries/fragments and unsafe schemes. Define the shared contracts above. WXT config forces MV3 for every target; optional host patterns enable chosen-instance access and optional website injection. Request no mandatory all-sites access. No `externally_connectable` or arbitrary page messaging. Add local fonts/assets only when Task 6 consumes them.
- [ ] Run unit tests, typecheck, and all three builds. Inspect generated manifests as JSON, not source strings, for MV3, minimum permissions, background entries and restrictive CSP. Commit: `feat: scaffold Vue browser extension`.

## Task 4: Durable tab-based OAuth and token lifecycle

**Files:** Create `extension/background/auth.ts`, `tests/unit/auth.test.ts`; wire `entrypoints/background.ts`. Reference, but do not import or modify, `mobile/src/auth/core.ts`.

**Interfaces:** `Auth` constructed with injected local storage, fetch, tab operations, and clock for deterministic tests. Methods `login(instance): Promise<void>`, `callback(tabId, url): Promise<void>`, `accessToken(): Promise<string>`, `logout(): Promise<void>`, `identity(): Promise<{instance: string; email: string} | null>`. Browser listeners register synchronously. Stored transaction contains instance, verifier, state, createdAt, exact tab ID; stored session includes identity/resource/client ID/token expiry and rotated refresh token. An account generation counter invalidates late asynchronous results.

- [ ] Write PKCE/state tests with independent RFC S256 vector, callback rejection table (wrong tab/state/issuer/path/origin, credentials, fragments, duplicates, both code/error, expired transaction), one-use success and user cancellation. Use injected deferred promises for refresh/logout ordering, not sleeps:

```ts
const tokens = await Promise.all([auth.accessToken(), auth.accessToken()]);
expect(tokens).toEqual(['new-access', 'new-access']);
expect(refreshRequests).toHaveLength(1);
```

`refreshRequests` is the test fetch recorder; fixture responses use distinct old/new refresh tokens. Reconstruct Auth over persisted storage before completing callback to model background restart. Logout before refresh completion must leave `identity()` null and storage cleared.
- [ ] Run `npm test -- tests/unit/auth.test.ts` and confirm new tests fail.
- [ ] Implement Web Crypto randomness and S256, official extension client ID from Task 1, resource `${instance}/api/v1`, four scopes, form-encoded token POSTs. Request chosen-instance permission in the user-click path before tab authorization. Create a blank authorization tab, persist transaction with its ID, then navigate it; cleanup incomplete transactions if navigation fails. Consume callback only after strict validation; serialize exchange and refresh; fail safely after ambiguous exchange/rotation instead of reusing a possibly consumed credential.
- [ ] Observe only the recorded tab. After consuming a callback, navigate that tab to the clean callback route and close it. Closing/cancelling the auth tab expires its pending transaction; never touch unrelated tabs. Restrict local storage to trusted contexts where supported. Clear local state first on Logout and revoke best-effort without logging credentials.
- [ ] Rerun tests/typecheck and builds; commit `feat: add extension OAuth and secure token lifecycle`.

## Task 5: Background API, preferences, and message boundary

**Files:** Create `extension/background/api.ts`, `preferences.ts`, `messages.ts`, `tests/unit/api.test.ts`, `messages.test.ts`, `preferences.test.ts`; update background entrypoint.

**Interfaces:** `Api.account(): Promise<AccountView>`, `aliases(search, page, recent?): Promise<AliasPage>`, `create(input): Promise<Alias>`. `handleMessage(message: unknown, sender): Promise<Reply<unknown>>` validates runtime shape and sender; UI calls through typed `request(message)` exported by `shared/contracts.ts`. Credentials never cross that boundary. Preferences keyed by normalized instance + authenticated email; domain falls back to current `default_domain` if no longer usable.

- [ ] Write tests for existing API wire responses, pagination/search encoding, recent enabled limit-three query, scope errors, machine-readable limit, domain fallback, per-account isolation, and stale responses after account switch. Unit fetch mock returns asymmetric domain names/alias titles; assert normalized results and correct selected domain rather than implementation calls alone.
- [ ] Test hostile messages: unknown type, URL override, extra credential fields, invalid create params, forged website sender requesting login/logout/preferences, absent tab/frame identity, and unregistered extension origin. Allow permitted content contexts only `account`, `aliases`, `create`, and authenticated billing navigation. Restrict management operations to own popup. Reject malformed messages with no network call.
- [ ] Run the new tests and confirm red.
- [ ] Implement fixed API paths under the authenticated instance, controlled query encoding and typed response validation. Refresh expired credentials once for safe reads; never blindly replay creation on transport or ambiguous auth errors. Map known failures to `Reply`; limit state uses capabilities, not list size. Account generation checks prevent late results being exposed or cached. Load all verified-domain pages rather than silently truncating the selector.
- [ ] Store nonsecret preferences locally; on entry query current permissions and capabilities. Separate requested API origin from optional all-website origins. Subscribe to permission changes and disable/unregister injection when website permission disappears, while retaining instance access. Validate browser sender identity at background boundary; no extension message channel available to page JavaScript.
- [ ] Run unit tests/typecheck, commit `feat: connect extension account operations and preferences`.

## Task 6: Paper-matched Vue toolbar popup

**Files:** Create `extension/popup/Login.vue`, `AliasList.vue`, `CreateAlias.vue`, `Settings.vue`, `useAccount.ts`, `assets/theme.css`, `assets/logo.svg`, `public/fonts/Inter.var.woff2`, and `tests/unit/popup.test.ts`. Update popup App/main.

**Interfaces:** `useAccount()` supplies account, page, query, creation state, preferences and typed background requests. UI state distinguishes idle/creating/created-copy-failed/error/uncertain; retain returned alias after clipboard failure. Login uses instance normalization from Task 3. Settings writes Preferences from Task 5. Keep component boundaries by screen; extract controls only when actually shared.

- [ ] Through Paper MCP retrieve full trees/styles/screenshots for `1BY-0`, `1C6-0`, `1C3-0`, `1OS-0`, `1BZ-0`, `1C4-0`, `1C1-0`, `1P8-0`, `1QB-0`, `1RT-0`, `1TB-0`. Inspect Phoenix `assets/css/app.css`, core controls, and locally available logo/font. Copy actual SVG and Inter file, including license as required. Do not reinterpret artboards from prose.
- [ ] Write mounted-component tests driven by accessible controls and asymmetric responses. Pin collapsed Server URL, defaults, account creation on selected instance, form metadata/domain, pending double click, limit rejection retaining values, clipboard-only retry and settings permission states. Slow search results must not replace newer query results:

```ts
await wrapper.get('input[type="search"]').setValue('old');
await wrapper.get('input[type="search"]').setValue('new');
resolveNewPage(); await flushPromises();
resolveOldPage(); await flushPromises();
expect(wrapper.find('[data-address="new@domain.example"]').exists()).toBe(true);
expect(wrapper.find('[data-address="old@domain.example"]').exists()).toBe(false);
```

Define the deferred page resolvers in this test's message fixture. No snapshot/source assertions. Double clicks produce one persisted alias; successful creation plus failed clipboard yields Copy for that same returned address and never a second create request.
- [ ] Run component tests and confirm red; implement Vue templates/actions with 360px popup width and Paper layout/tokens. Tailwind v4 utilities, local font faces, system/light/dark appearance and accessible focus controls. Preserve copy, search pagination, alias statuses, descriptions, domain choices and usage/Upgrade. Signup and billing use connected instance routes. Default settings icon off; conditional Allow website access invokes permission request directly from gesture.
- [ ] Model loading, empty search, session expiry, cancellation and uncertain transport without hiding entered values. On creation success copy returned address, reload page/capabilities, show brief confirmation. On uncertainty refresh aliases before allowing another explicit create attempt; never claim creation failed definitively.
- [ ] Run component tests/typecheck/build; render representative states with deterministic test responses, capture screenshots and inspect with `view_media` against corresponding Paper captures. No production-only fixture screens in extension output. Commit `feat: implement Paper extension popup in Vue`.

## Task 7: Optional email-field icon, inline menu, and browse picker

**Files:** Create `extension/entrypoints/email-fields.content.ts`, `content/fields.ts`, `content/InlineMenu.vue`, `tests/unit/fields.test.ts`, `tests/unit/inline-menu.test.ts`. Update background optional content registration and permission lifecycle.

**Interfaces:** `discoverFields(root): HTMLInputElement[]` accepts editable visible email inputs. `fillField(input, address): boolean` sets selected input through native setter and dispatches bubbling input/change, returning false if detached/readonly/disabled. Inline menu consumes Task 5 account/recent/create APIs. Browse all is a searchable extension-owned picker in the same Shadow DOM; retains the original element reference and frame, not a CSS selector that could match a replacement.

- [ ] Through Paper MCP inspect `1C2-0`, `1WC-0`, `1XT-0`, `1TT-0` and behavior handoff `1C5-0`. If expanded browse picker layout needs design beyond these artboards, raise that gap before inventing a new screen; reuse the approved alias-list treatment where it fits and seek design confirmation for the missing state.
- [ ] Write field tests for initial/dynamic inputs, disabled/readonly/hidden fields, frame isolation, native setter and both events without submit, replacement during async creation and no duplicate create. Pin the replacement boundary:

```ts
const original = document.createElement('input'); original.type = 'email';
document.body.append(original);
const replacement = original.cloneNode() as HTMLInputElement;
original.replaceWith(replacement);
expect(fillField(original, 'kept@domain.example')).toBe(false);
expect(replacement.value).toBe('');
```

- [ ] Write menu tests: recent enabled aliases account-wide max three, Fill email vs create, domain selector only with multiple choices, remembered selection, server-provided limit disables creation while fill/browse remain usable, Escape/outside click/focus restoration. Permission revocation tears down roots and observers. Lost target after successful creation offers Copy for the returned alias without another POST.
- [ ] Run tests and confirm red; implement Shadow DOM Vue UI with bundled styles/logo, isolated observers and lifecycle cleanup. Inject only with permission + icon enabled; permitted frames use their own field identity. Initial scan plus mutation/resize/scroll handling; observe attributes affecting editability. Prevent controls from covering existing password-manager affordances; clamp menu to viewport. Do not modify page styles globally or submit forms.
- [ ] Implement browse/search/pagination inside the extension-owned menu, retaining original target context. Background never accepts an arbitrary fill destination; filling happens in originating content context. Creation is only a deliberate click; block duplicates, retain successful addresses on failed fill/copy.
- [ ] Run unit/component tests and real website fixtures from Task 8. Inspect inline screenshots for default/custom-domain/open-selector/limit and narrow viewport states. Commit `feat: add optional email-field alias filling`.

## Task 8: Real browser journey and cross-browser packaging

**Files:** Create `extension/playwright.config.ts`, `tests/e2e/extension.spec.ts`, `fixtures.ts`, `website.html`, `scripts/package-safari.sh`. Extend extension README; add deterministic extension scenario setup under `shroud.email/priv/repo/extension_e2e_seeds.exs` only for isolated local E2E databases. Reference current `shroud.email/scripts/run_e2e_tests.sh`, `compose.e2e.yaml` and `e2e/` patterns before introducing another environment harness.

**Interfaces:** `npm run test:e2e` launches real Chromium with built unpacked MV3 extension and local Phoenix. Deterministic website fixture has two distinct email inputs, dynamic input, iframe, input/change counters and submit counter. Test fixtures supply confirmed accounts, free-capacity/free-limit/paid/custom-domain scenarios. Never seed/reset a shared or production database.

- [ ] Write journey before final wiring: select loopback instance, grant only instance permission, OAuth browser sign-in/consent, reopen popup, create/copy, search/pagination, custom-domain alias, reach authoritative free limit, grant website permission then enable icon, fill selected input and assert sibling/submit untouched, Browse all fill, logout. Use real OAuth/API backend; mock only external email/billing/DNS via existing deterministic seams.

```ts
await site.getByLabel('Work email').focus();
await site.getByRole('button', {name: 'Use a Shroud.email alias'}).click();
await site.getByRole('button', {name: 'Create & fill', exact: false}).click();
await expect(site.getByLabel('Work email')).toHaveValue(/@/);
await expect(site.getByLabel('Backup email')).toHaveValue('');
await expect(site.locator('#submit-count')).toHaveText('0');
await expect(site.locator('#input-count')).toHaveText('1');
await expect(site.locator('#change-count')).toHaveText('1');
```

The fixture exposes counters through text elements. Assert resulting alias appears in the real account list and correct domain suffix; do not use a generic `@` check as the only creation assertion. Chromium launch uses persistent context with built extension directory; inspect actual popup/background/content messaging, not a standalone web approximation.
- [ ] Run journey to identify missing integration. Finish wiring, verify permission loss, authorization cancellation, reload/background restart and clipboard/target failure with browser-level exercises. Unit injection remains supplementary for exact race cases. Use condition-based waits, not sleeps.
- [ ] Run typecheck, unit/component suite, and Chrome/Firefox/Safari production builds. Inspect generated manifest permissions, CSP and packaged resources. Run Firefox unpacked behavior where supported local tooling allows. Package Safari via `xcrun safari-web-extension-packager`, fallback to converter only if installed packager unavailable, with unsigned local output. Exercise desktop Safari if local enablement/automation permits; report package-only verification separately if not. No automatic signing or store upload.
- [ ] Capture every Paper state and additional interaction states in real rendering. Inspect each screenshot with `view_media` naming expected layout/copy/colors/radii. Fix differences, recapture, expose only final images. Keep browser/backend dev servers running if started for review; owner is remote, so describe runner/port rather than implying their localhost works.
- [ ] Add README commands for npm/mise, backend migration requirement, loading unpacked Chrome/Firefox, Safari packaging/enablement, self-host compatibility, optional permissions, verification limits and release boundaries. Commit `test: verify extension journeys and browser packages`.

## Task 9: Combined verification and delivery review

**Files:** Existing changed files only; no extra product scope. Add root `.github/workflows/extension.yml` if current CI patterns permit a focused extension job; follow pinned-action and lockfile conventions. README records executable checks, not unexecuted promises.

- [ ] Run from `shroud.email/`:

```sh
mise exec -- mix test
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix credo --strict
mise exec -- mix sobelow --config
```

- [ ] Run from `extension/`:

```sh
mise exec -- npm ci
mise exec -- npm test
mise exec -- npm run typecheck
mise exec -- npm run build:chrome
mise exec -- npm run build:firefox
mise exec -- npm run build:safari
mise exec -- npm run test:e2e
mise exec -- npm run package:safari
```

- [ ] Inspect diff for unrelated edits, leaked credentials, uncontrolled network paths, unsafe scope/redirect expansion, duplicate mutation retries and missing Paper states. Check `.amp/in/` artifacts are locally excluded. Distinguish existing failures from regressions without suppressing either.
- [ ] Add focused CI unit/type/build checks using this project's lockfile, not root npm. Do not trigger external CI/deployments manually. Commit verified CI/docs corrections only if needed.
- [ ] Obtain the review required by the chosen execution skill in the workspace containing the exact changes; address findings and rerun affected checks. Deliver local branch state, executed browser matrix, final screenshots and remaining authorization boundaries. Do not push, deploy, or claim all-browser runtime validation on build evidence alone.

## Plan self-review

Spec coverage: Tasks 1–2 own server policy/API compatibility; Tasks 3–5 own MV3/OAuth/permissions/messages; Tasks 6–7 own every approved Paper screen and interaction; Tasks 8–9 own integration, visual comparison, browser matrix and delivery. Review-focus cases have explicit tests in their owning tasks. Shared message/types are defined once and consumed by name. An undesigned expanded browse picker is an explicit design gate rather than an invented modal. Browser runtime limitations must appear in the final report.
