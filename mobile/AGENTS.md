# Shroud.email mobile

- Run commands from `mobile/`. Use npm and this project's `package-lock.json`;
  root npm dependencies are only repository maintenance tooling.
- Node.js is pinned by the root `mise.toml`.
- This is a managed Expo app with TypeScript and Expo Router. Routes live in
  `src/app/`. Keep native `ios/` and `android/` folders generated and ignored.
- Start the Expo dev server with `EXPO_UNSTABLE_MCP_SERVER=1`, for example
  `EXPO_UNSTABLE_MCP_SERVER=1 npx expo start`. Local MCP capabilities require
  `expo-mcp` and Expo CLI authentication with the same account as the MCP connection.
  Reconnect the Expo MCP connection after starting or stopping the dev server.
- Verify changes with `npx tsc --noEmit`, `npm run lint`, and `npx expo-doctor`.
  Use `npx expo export --platform all` to check bundling for iOS, Android, and web.
- The browser preview is not a substitute for native device testing. Local iOS
  simulator development requires macOS and Xcode.

## Imported Expo template notice

The following original notice is retained for the copied starter code and artwork.

```text
The MIT License (MIT)

Copyright (c) 2015-present 650 Industries, Inc. (aka Expo)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
