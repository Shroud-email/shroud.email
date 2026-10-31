#!/usr/bin/env bash
set -euo pipefail

destination="${1:?Usage: fetch-timeless.sh DESTINATION}"
checksum=353b3fbb75b8e9b927db12d520ff8d446d89c36897b47a90d70dbe36e9eeb23a
font="$destination/TimelessSansVF.woff2"

# The license permits web embedding, but not public-repository redistribution.
if [[ -f "$font" && -f "$destination/LICENSE.pdf" ]] &&
  printf '%s  %s\n' "$checksum" "$font" | sha256sum --check --status; then
  exit 0
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

curl --fail --silent --show-error --location --retry 3 \
  https://media.timeless.co/type/Timeless-Type-Family-1.094.zip \
  --output "$temporary/timeless.zip"
unzip -p "$temporary/timeless.zip" \
  Timeless-Type-Family-1.094/Sans-Grotesk/TimelessSansVF.woff2 \
  > "$temporary/TimelessSansVF.woff2"
unzip -p "$temporary/timeless.zip" Timeless-Type-Family-1.094/LICENSE.pdf \
  > "$temporary/LICENSE.pdf"
printf '%s  %s\n' "$checksum" "$temporary/TimelessSansVF.woff2" | sha256sum --check

mkdir -p "$destination"
cp "$temporary/TimelessSansVF.woff2" "$temporary/LICENSE.pdf" "$destination/"
