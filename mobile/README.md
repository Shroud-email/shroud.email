# Shroud.email mobile

React Native app scaffolded with `create-expo-app`'s default template (Expo SDK
57, TypeScript, and Expo Router). The Home and Explore starter screens and Expo
artwork are retained, with small tooling and hydration fixes; authentication
and REST API integration are not implemented yet.

This project has its own npm dependencies and lockfile. Run commands from
`mobile/`, not the repository root. It inherits the root mise Node.js version.

## Development

```sh
npm ci
npm start
```

Scan the terminal QR code with a compatible version of Expo Go on your phone,
or use a [development build](https://docs.expo.dev/develop/development-builds/introduction/)
if your Expo Go version does not support this SDK.

Other entry points:

- `npm run android`: start on an Android emulator or connected device (requires
  Android tooling).
- `npm run ios`: start on an iOS simulator (requires macOS and Xcode).
- `npm run web`: preview the same app in a browser.

Routes live in `src/app/`; shared components, hooks, and theme constants live in
`src/components/`, `src/hooks/`, and `src/constants/`. App identity and Expo
configuration are in `app.json`. Store bundle identifiers and EAS configuration
are intentionally left unset until native distribution is needed.

## App icons

The app display name is **Shroud.email**. Icons use the existing striped-circle
mark from `../website/public/img/logo.svg` in white on `#151726`, the sRGB
equivalent of the website's purple-tinted dark surface (`oklch(0.21 0.03 277)`).

- `assets/images/icon.png`: opaque 1024×1024 icon for iOS and legacy Android.
  Corners are square; the operating system applies its own mask.
- `assets/images/android-icon-foreground.png`: transparent 1024×1024 adaptive
  layer with a centered 512×512 mark, inside Android's safe zone. The background
  color is configured separately in `app.json`.
- `assets/images/android-icon-monochrome.png`: the same white alpha mask for
  Android themed icons. The launcher supplies the colors.
- `assets/images/favicon.png`: 48×48 version for the browser preview.

These are rasterized from the SVG, not an AI-redrawn logo. Launcher icon changes
require a new native build; Expo Go continues to use its own launcher icon.

To replace the examples with a blank app later, run `npm run reset-project`.
This moves the example source to `example/` and creates a minimal `src/app/`.

## Verification

```sh
npm test
npx tsc --noEmit
npm run lint
npx expo-doctor
npx expo export --platform all
```

Exports go to the ignored `dist/` directory. Native exports verify JavaScript
bundling, not compilation or behavior on an actual iOS or Android device.

The xcode dependency is overridden to use patched UUID 11.1.1; it only calls the
compatible CommonJS `v4()` API. `npm audit` still reports transitive findings for
`decode-uri-component` through Expo Router's CommonJS `query-string@7`. The fixed
decoder version is ESM-only and is not a drop-in override for that consumer.
Do not use `npm audit fix --force`: its suggested fixes downgrade core Expo
packages across SDK versions. Recheck these findings when upgrading Expo.

## License

The mobile app follows the repository's AGPL-3.0 license (see the
[root LICENSE](../LICENSE)).

The source and artwork copied from the Expo starter template retain their
original MIT notice below. This attribution is for the copied template, not
for modifications to Expo itself.

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
