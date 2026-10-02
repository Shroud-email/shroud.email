# Shroud.email mobile

The alias UI implements the approved Paper designs in light and dark mode with
Phosphor action/navigation icons. Aliases have no icons of their own.

## Preview boundaries

- `src/providers/auth-stub.tsx` is an explicit, credential-free auth stub. It
  starts the UI preview as `alex@example.com`; logout shows a placeholder, not
  a login screen. Replace it with the OAuth session provider separately.
- `src/providers/app-provider.tsx` owns the demo aliases and domains. Creation,
  editing, forwarding toggles and confirmed deletion operate **in memory**;
  they reset on reload and never contact the backend or change real email.
- Appearance is stored locally, independently of authentication. System mode
  follows device appearance. Random addresses and forwarding counts are demo
  data, not server-generated results.
- Routes: `(tabs)/index` (list), `(tabs)/settings`, `create`, `aliases/[id]`.

## Development

```sh
npm ci
npm start
```

## Android

```sh
npm run android
```

## iOS

```sh
npm run ios
```

## Web

```sh
npm run web
```

## Verification

```sh
npm test
npx tsc --noEmit
npm run lint
npx expo-doctor
npx expo export --platform all
```
