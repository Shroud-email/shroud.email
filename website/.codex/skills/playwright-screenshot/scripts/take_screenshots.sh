#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <url> [output_dir] [widths_csv] [height]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

url="$1"
out_dir="${2:-./screenshots}"
widths_csv="${3:-1440,1200,1024,768,375}"
height="${4:-900}"

mkdir -p "$out_dir"

IFS=',' read -r -a widths <<< "$widths_csv"
for w in "${widths[@]}"; do
  w_trim="$(echo "$w" | xargs)"
  if [[ -z "$w_trim" ]]; then
    continue
  fi
  out_file="$out_dir/${w_trim}w.png"
  npx playwright screenshot "$url" "$out_file" --viewport-size="${w_trim},${height}" --full-page
  echo "Saved $out_file"
done
