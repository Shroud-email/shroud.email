# Shroud.email mobile

## Development

```sh
npm ci
npm start
```

## Native sign-in

The app uses public client ID `3dab4011-1a87-453f-9b6d-c8e12a41c892`, provisioned
in the server's database by migrations. There is no client secret or client-ID
environment variable. The callback is `https://app.shroud.email/oauth/callback`,
the resource is `https://app.shroud.email/api/v1`, and the scopes are
`profile:read aliases:read aliases:create aliases:edit aliases:delete domains:read`.
The app connects to the hosted server; instance selection is not supported.

Use an installed native build with the existing `email.shroud.app` identity and
verified HTTPS links (including the server's Apple/Android association files).
Expo Go does not verify native universal links. The app targets iOS and Android
only. iOS requires 17.4+ for secure HTTPS auth-session callbacks; older iOS is
explicitly unsupported.

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

## Verification

`npm test` runs the Node script tests and React Native Testing Library integration
tests. The integration tests render the home screen with its auth provider and
real React hooks. Native APIs and network requests use test doubles; these tests
do not replace native device testing.

```sh
npm test
npx tsc --noEmit
npm run lint
npx expo-doctor
npx expo export --platform all
```
