# Shroud.email mobile

- Run commands from `mobile/`. Use npm and this project's `package-lock.json`;
  root npm dependencies are only repository maintenance tooling.
- Node.js is pinned by the root `mise.toml`.
- This is a managed Expo app with TypeScript and Expo Router. Routes live in
  `src/app/`. Keep native `ios/` and `android/` folders generated and ignored.
- Verify changes with `npx tsc --noEmit`, `npm run lint`, and `npx expo-doctor`.
  Use `npx expo export --platform all` to check bundling for iOS, Android, and web.
- The browser preview is not a substitute for native device testing. Local iOS
  simulator development requires macOS and Xcode.
