# Shroud.email browser extension

## Goal and scope

Implement the approved browser-extension designs in one codebase for desktop Chrome, Firefox, and Safari. Users sign in with OAuth, create and copy aliases from the toolbar popup, and optionally create or fill aliases in website email fields. Support hosted Shroud.email and self-hosted instances.

Required UI designs: https://app.paper.design/file/01M3VEVRW9WWCGNZH64T87G0SP/p-2-0

The Paper designs are the source of truth for the extension's layout, styling, copy, and designed states, not optional inspiration. Implementers must access this file through the Paper MCP tools before planning or implementing UI. Inspect the relevant artboards, node hierarchy, computed styles, and screenshots; do not reconstruct the designs from this spec's prose or conversation screenshots alone. Use file ID `01M3VEVRW9WWCGNZH64T87G0SP` and page ID `p-2-0`.

Preserve the Paper designs and the behavior requirements in this spec. If they conflict or a required state is not designed, raise that gap before introducing a different layout or interaction. If the Paper MCP tools are unavailable, report the blocker rather than substitute an inferred design.

This is a new `extension/` project with its own npm lockfile. Root npm dependencies remain repository-maintenance tooling. Phoenix owns account policy, OAuth, domain validation, and alias creation. Store publishing, production migrations, signing, and deployments require separate authorization.

## Browser architecture

Use WXT, TypeScript, Vue 3, and Tailwind CSS v4. Build Manifest V3 outputs for Chrome, Firefox, and Safari explicitly; do not rely on WXT's per-browser default manifest versions.

Share popup components, content-script UI, API contracts, OAuth logic, and tests. Keep browser differences in manifest/build configuration and small platform operations only where required by tested API differences.

The background context owns OAuth transactions, tokens, refresh serialization, authenticated API calls, and account-scoped preferences. The popup and content script use typed extension messages. Web pages never receive OAuth tokens or PKCE verifiers. Treat content-script messages as untrusted input: allow only the defined alias operations, not arbitrary URLs or fetch requests.

Use an isolated Shadow DOM for the email-field icon and menu. The browser popup is separate from the injected menu. Neither UI depends on Phoenix rendering inside the extension.

Safari uses the same built web resources in an Apple-generated Xcode wrapper. Include a reproducible packaging command for the installed `safari-web-extension-packager`, with the converter name as a compatibility fallback. Initially validate desktop Safari on macOS; iOS Safari packaging is possible but not part of the initial verification claim.

## OAuth and instance selection

OAuth authorization-code flow with S256 PKCE is the only extension login method. Do not use `/api/v1/token`, collect passwords, reuse the mobile client identity, or broaden public MCP client registration to permit API clients.

Use a first-party public extension OAuth client with only `profile:read`, `aliases:read`, `aliases:create`, and `domains:read`. Register its exact callback on each instance's canonical issuer. Local registration must support development and self-hosting without accepting arbitrary redirect URLs or redirect wildcards. Follow the existing official-client TTL, revocation, and consent policies.

Use tab-based authorization across all three browsers because Safari does not support `identity`. Open `/oauth/authorize` in a new tab after the user clicks Sign in. Receive the response at an instance-owned `/oauth/extension/callback` page. The background context observes navigation in the specific authorization tab and exchanges the code.

Persist the pending transaction before navigation so background suspension does not lose it. Validate the exact callback origin/path, tab ID, state, issuer, transaction age, and duplicate query parameters. Reject credentials in the callback URL, mismatched transactions, fragments, and unexpected issuer changes. Consume a successful transaction once. Exchange and refresh tokens only in POST bodies. Close the authorization tab after completion and leave the popup ready to reopen.

The callback page uses `Cache-Control: no-store` and `Referrer-Policy: no-referrer`; it does not load third-party assets or analytics. Scrub callback credentials from its address once they have been consumed.

Use `https://app.shroud.email` by default. Login shows Sign in, Create account, and a small collapsed Server URL disclosure at the bottom. Expanding it reveals the editable URL without self-hosting explanation text. Both actions use the selected instance.

Accept HTTPS origins, plus HTTP localhost/loopback for local development. Reject userinfo, queries, fragments, and non-root paths. Request permission for the chosen instance before OAuth/API access. Do not silently fall back to the hosted instance on an error.

Keep tokens in extension-owned local storage, not sync storage or page storage. Restrict storage access to trusted extension contexts where the browser supports that restriction. No credentials appear in logs, screenshots, content-script responses, or website DOM. Serialize refreshes in the background context; do not replay a creation request after an ambiguous transport failure.

Logout clears local credentials, pending transactions, account caches, and account-scoped preferences. Attempt server revocation without preventing local logout when offline. Never close or navigate unrelated browser tabs.

## Phoenix API requirements

Reuse the existing alias list/search/create API, verified-domain API, profile API, and OAuth endpoints. Make compatible additions rather than replace existing response contracts.

Add a scoped alias-capabilities endpoint with authoritative non-deleted alias count, nullable alias limit, creation eligibility, and the default shared domain. Use the same account policy as alias creation. Do not infer free/paid status from list length or hard-code five in the extension. Keep `/me`'s existing email response compatible.

Extend alias creation to support random names on the requested domain as well as explicit custom names. The default shared domain and the current user's verified custom domains are the allowed choices. Validate ownership and current verification on the server; the domain-list response alone is not authorization. Reuse alias-generation and validation logic rather than generate random addresses in the extension.

Retain existing create requests with no address fields and requests with both `local_part` and `domain`. Add a stable machine-readable error code for the free-limit response while preserving the existing human-readable error. Update OpenAPI schemas and targeted Phoenix tests with each API change.

## Popup and creation

- Alias list: newest first, searchable, paginated, with address, description, status, and copy action. No Open Shroud.email footer or header logo.
- Create form: random/custom-name choice, domain selector, optional description, and Create & copy alias. Do not display a generated random address before creation. Map description to the API's `title` field.
- During creation: show Creating… and prevent duplicate requests. Preserve form values on failure.
- On success: copy the returned address, return to the alias list, refresh usage, and show a brief Alias created and copied confirmation. There is no separate Alias copied screen.
- If creation succeeds but copying fails: retain the created address and offer Copy. Never create a replacement alias for a clipboard failure.
- If creation fails: keep the form available for retry with a clear message. Do not show Use an existing alias as a separate failure action.
- If server response is ambiguous after a network failure: do not auto-retry a POST or report that no alias exists. Refresh the list before offering another creation.

## Website email-field shortcut

Default Show icon in email fields to off. Request website permission only after an explicit user action. Keep permission to access the connected API instance separate from permission to inject into arbitrary websites. Do not require access to every website merely to use the toolbar popup.

The icon inside an editable email field is the actual Shroud.email SVG logo. The menu's heading is Use a Shroud.email alias; its creation button is + Create & fill, without a logo in that button.

Discover email inputs in initial and dynamically inserted forms. Support editable inputs in permitted frames. Do not overlap existing password-manager controls. Reposition or constrain the menu to fit the viewport. Close on Escape/outside click, restore focus, and provide keyboard-operable controls and accessible labels.

Create & fill creates only after a click, fills only the selected input, and dispatches input/change events needed by the page. Never submit the website's form. If the target disappears or becomes non-editable after creation, keep the returned alias and offer Copy instead of creating again.

Show up to three most recently created enabled aliases, newest first, under Recent aliases. Each has a Fill email action. The list is account-wide, not website-associated or domain-filtered. Browse all aliases opens a searchable extension-owned alias picker that retains the selected tab/frame/input context; selecting an alias fills that original field. Do not depend on programmatically opening the toolbar popup, which differs between browsers.

Show Domain above Create & fill only when more than one usable domain exists. Start with the account default, include verified custom domains, and remember selection per account and server. If a remembered domain is no longer usable, select the current default. Selection affects creation only, not recent aliases. Users with one usable domain retain the simpler menu.

## Settings and free limits

Settings include Show icon in email fields, System/Light/Dark appearance, account identity, and Logout. Do not show a Website access status row or Manage browser permissions link. Show Allow website access immediately below the icon toggle only when permission is missing. Remove it after permission is granted.

At the creation limit, show Alias limit reached, server-provided usage/limit, and Upgrade. Disable New alias, Create & copy alias, and Create & fill. Search, copy, and filling existing aliases remain usable. Upgrade opens `/settings/billing` on the connected instance.

The current free limit is five non-deleted aliases; disabled aliases count. Paid accounts are not treated as free because they have five aliases. If another client consumes capacity while the form is open, preserve entered values and render the same limit state after server rejection. Refresh capabilities on popup/menu entry and after successful creation.

## Visual system

Use Shroud.email consistently as the product name. Match Phoenix's Inter typography, six-pixel control corners, indigo button/link roles, gray light surfaces, remapped slate dark surfaces, green/red status pills, borders, focus treatments, and subtle shadows. Use the actual logo and locally packaged fonts; do not load fonts or executable code from a remote CDN.

Paper's complete states include light/dark popup, login disclosure closed/open, pre-creation form, failure, settings permission granted/missing, inline menu, custom-domain selector closed/open, and free-limit variants. Also render loading, empty search, logout/expired-session, clipboard/fill failures, and consent-cancelled states during implementation.

## Verification and delivery

Before planning or implementing, fetch current `origin/main` and rebase unpublished feature commits onto it, preserving uncommitted work. Do not rewrite published history without explicit approval. After synchronization, read the root `AGENTS.md` and every scoped `AGENTS.md` governing the files being changed, especially `shroud.email/AGENTS.md` for backend work. Follow their current testing guidance and project-local commands; this spec does not replace repository instructions.

Follow the repository's testing philosophy: test observable outcomes rather than implementation details. Keep tests focused on plausible failures, with independently derived expectations and inputs that distinguish correct behavior from a likely wrong implementation. For Phoenix, use ExUnit, existing fixtures, and Mox behaviours for external services to keep tests deterministic. For LiveView changes, use DOM-aware selectors and stable element IDs rather than raw HTML comparisons. Apply the same outcome-focused approach to Vue components and extension integration tests; do not substitute snapshots, source-text assertions, or mocked browser APIs for exercising real browser integrations.

Use TDD for API policy, OAuth validation, message boundaries, creation state transitions, and field discovery/filling. Use asymmetric inputs and concurrency/lifecycle boundaries: wrong issuer/state/tab, duplicate callbacks, refresh rotation, background restart, account switch, stale usage, unverified foreign domains, double clicks, missing inputs, and create-success/copy-failure.

Run targeted Phoenix tests plus formatting, compile, Credo, and Sobelow for affected backend code. Run extension unit/component tests, TypeScript checks, and production builds for all three targets. Verify manifest permissions and ensure credentials are excluded from public/content-script data.

Exercise the real Chromium extension with a local Phoenix instance and deterministic website fixtures. Inspect screenshots for every affected visual state, in light and dark modes. Validate Firefox and Safari locally where installed tooling allows; distinguish build/package success from executed browser behavior. Safari signing, App Store submission, production registration/migrations, and store publishing remain outside local implementation delivery.

Compare rendered UI screenshots against the corresponding Paper artboards retrieved through the Paper MCP tools. Verify layout, typography, colors, spacing, radii, icons, and copy for each designed state; correct discrepancies before declaring the UI complete.

## Technical references

- WXT browser targets: https://wxt.dev/guide/essentials/target-different-browsers
- Apple API compatibility, including unsupported identity: https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility
- Safari packaging: https://developer.apple.com/documentation/safariservices/packaging-a-web-extension-for-safari

This spec is approved for implementation planning. Product code follows review of the task-by-task implementation plan.
