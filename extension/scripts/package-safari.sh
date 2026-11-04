#!/usr/bin/env bash
set -euo pipefail
tool=safari-web-extension-packager
if ! xcrun --find "$tool" >/dev/null 2>&1; then tool=safari-web-extension-converter; fi
xcrun "$tool" .output/safari-mv3 --project-location safari --app-name Shroud.email --bundle-identifier email.shroud.Shroud-email --macos-only --swift --copy-resources --no-open --no-prompt --force
