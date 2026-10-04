# Shroud.email mobile

## Development

```sh
npm ci
npm start
```

## Native sign-in

Set `EXPO_PUBLIC_OAUTH_CLIENT_ID` to the backend's pre-registered public client
UUID before starting Metro or building. There is no client secret. The client
must permit `https://app.shroud.email/oauth/callback`, resource
`https://app.shroud.email/api/v1`, and scopes `profile:read aliases:read
aliases:create aliases:edit aliases:delete domains:read`.

Use an installed native build with the existing `email.shroud.app` identity and
verified HTTPS links (including the server's Apple/Android association files).
Expo Go and the web preview are not native universal-link verification. Web
sign-in is intentionally disabled and stores no credentials. iOS requires 17.4+
for secure HTTPS auth-session callbacks; older iOS is explicitly unsupported.

Tokens and ten-minute pending PKCE transactions use native SecureStore. Account
identity is fetched on launch, return to foreground, and every minute. Refreshes
serialize and persist each rotation; interrupted or ambiguous exchanges require
signing in again rather than replaying credentials. The backend enforces the
90-day connection lifetime. Offline logout clears local credentials but cannot
revoke the server connection: revoke it in account settings when online.

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
