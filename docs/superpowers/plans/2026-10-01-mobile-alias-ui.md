# Mobile alias UI implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved mobile alias screens in the existing Expo app, excluding login and OAuth.

**Architecture:** Expo Router stack with Aliases/Settings tabs, a create screen, and alias detail routes. An in-memory demo alias store behind a provider makes the UI interactive without authentication or production writes. Only appearance persists locally. A separate auth stub exposes the preview user and logout boundary for later OAuth integration.

**Tech Stack:** React Native, Expo 57, TypeScript, Expo Router, Manrope, Expo Clipboard, AsyncStorage, Phosphor/react-native-svg, Node tests.

**Spec:** [Approved Paper screens](https://app.paper.design/file/01M3VEVRW9WWCGNZH64T87G0SP/p-1-0), including dark/light, random/custom creation, disabled domains, and inline title/notes editing.

## Global constraints

- No login screen, OAuth implementation, Spam tab, password/security/email/plan management.
- Match Paper's compact layout, full addresses, no alias icons, and no empty description slot.
- Alias name precedes Domain; unverified domains are visible but disabled. No verified caption.
- Settings contains read-only email, System/Light/Dark, and logout only.
- Do not touch the Phoenix backend. Demo data is not a real authenticated account.
- Preserve existing dark/light behavior and platform-safe navigation, scrolling, keyboard handling, and accessibility.

## Review focus

- Search and status filters intersect correctly; blank titles never become placeholder descriptions.
- Custom creation cannot use an unverified domain or create a duplicate address.
- Saving empty titles/notes clears them; cancelling edits preserves the prior value.
- Delete requires confirmation; cancelling it never mutates data.
- Persisted theme respects System, with matching navigation, status bar, and form colors.

## Task 1: Alias model and auth boundary

**Files:** `mobile/src/data/aliases.ts`, `mobile/scripts/aliases.test.js`, `mobile/src/providers/app-provider.tsx`, `mobile/src/providers/auth-stub.tsx`.

- [x] Write Node tests against the real model for filtering across address/title/notes, combined filters, verified-domain validation, duplicate detection, title/notes clearing, targeted toggling, and deletion.
- [x] Run `npm test`; confirm new tests fail because the model does not exist.
- [x] Implement typed alias/domain data, demo fixtures, validation, and immutable mutations. Tests import the TypeScript module using Node's type stripping.
- [x] Run `npm test` and verify all tests pass.
- [x] Add the auth stub and provider; keep demo mutations in memory and persist only appearance. Logout renders a minimal auth placeholder, not a login form.

## Task 2: Theme and navigation

**Files:** `mobile/src/constants/theme.ts`, `mobile/src/hooks/use-theme.ts`, `mobile/src/components/themed-text.tsx`, `mobile/src/components/ui.tsx`, `mobile/src/app/_layout.tsx`, `mobile/src/app/(tabs)/_layout.tsx`.

- [x] Install Expo-compatible Clipboard, AsyncStorage, SVG, Phosphor and Manrope fonts with the mobile lockfile.
- [x] Use Paper's exported values: dark `#0F172A`/`#1E293B`/`#334155`, light white/`#F8FAFC`/`#E2E8F0`, theme-specific indigo and readable status colors.
- [x] Load Manrope and remove the starter splash overlay from navigation.
- [x] Implement shared text, controls, headers and Phosphor action icons; use native safe areas and platform status bars rather than drawing OS chrome.
- [x] Add a root stack and exactly two tabs: Aliases and Settings. Creation/details hide the tab bar.

## Task 3: Alias screens and settings

**Files:** `mobile/src/app/(tabs)/index.tsx`, `mobile/src/app/(tabs)/settings.tsx`, `mobile/src/app/create.tsx`, `mobile/src/app/aliases/[id].tsx`, `mobile/README.md`.

- [x] Build the list with address/title search, All/Enabled/Disabled, full-address copy, feedback, empty states, and description-free single-line rows.
- [x] Build random/custom creation: no editable random name or fake generated preview; custom name then domain, disabled unverified menu options, preview, validation, and create-to-details navigation.
- [x] Build details with copy, forwarding toggle, independent title/notes Save/Cancel, counts, recipient, and confirmed deletion back to the list.
- [x] Build minimal settings with email, persisted appearance, and stub logout.
- [x] Remove starter screens and source helpers that exist only for them; document the demo/auth boundary and commands.

## Task 4: Verification

- [x] Run `npm test`, `npx tsc --noEmit`, `npm run lint`, `npx expo-doctor`, and `npx expo export --platform all` from `mobile/`.
- [x] Render the browser app and exercise filters, clipboard feedback, random/custom creation, disabled-domain rejection, edit Save/Cancel, toggle, confirmed/cancelled delete, theme persistence and logout.
- [x] Capture and inspect dark/light list, form/open menu, details/editing and settings. Simulator testing was stopped at the user's request; no completed native-interaction verification is claimed.
- [x] Leave the browser preview running, report local uncommitted delivery state and inspect the final diff. Do not push or merge.

Verification: 9 Node tests pass, TypeScript and lint pass, Expo Doctor passes 21/21,
and all three platform exports succeed. Browser error console is clear after the
rendering fixes. Preview port: 8082. Review captures: `.amp/in/artifacts/` (ignored).
