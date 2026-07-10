#!/usr/bin/env bash
set -euo pipefail

compose=(docker compose -f compose.e2e.yaml -p shroud-e2e)

cleanup() {
  status=$?
  if [[ $status -ne 0 ]]; then
    "${compose[@]}" logs app db mailpit || true
  fi
  "${compose[@]}" down --volumes --remove-orphans
  exit "$status"
}

trap cleanup EXIT INT TERM

"${compose[@]}" build app
"${compose[@]}" up --abort-on-container-exit --exit-code-from playwright playwright
