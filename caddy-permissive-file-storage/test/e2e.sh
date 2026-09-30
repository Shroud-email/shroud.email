#!/usr/bin/env bash
# E2E test: build Caddy with the local permissive-file-storage plugin,
# run it with tls internal, and assert on-disk cert/key permissions.
#
# Catches: Store() signature drift (compile failure), permission regressions
# (0644/0755 -> 0600/0700), and module wiring breakage.
#
# Run locally:  bash test/e2e.sh
# Run in CI:    see .github/workflows/deploy.yml (test job)
#
# Exits 0 on success, non-zero on failure. Never self-skips: missing xcaddy
# or a port collision is a real failure, not a pass.

set -euo pipefail
umask 022

# --- config ---
CADDY_VERSION="v2.10.0"   # keep in sync with go.mod's caddy/v2 requirement
HTTP_PORT=8080
HTTPS_PORT=9443
PLUGIN_MODULE="github.com/Shroud-email/caddy-permissive-file-storage"

# --- fail if xcaddy is not installed ---
if ! command -v xcaddy >/dev/null 2>&1; then
  echo "FAIL: xcaddy not found on PATH; install with 'go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest'" >&2
  exit 1
fi

# --- fail if ports are taken ---
port_taken() { (echo >"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
if port_taken "$HTTP_PORT" || port_taken "$HTTPS_PORT"; then
  echo "FAIL: port $HTTP_PORT or $HTTPS_PORT is already in use" >&2
  exit 1
fi

# --- temp dirs ---
WORKDIR="$(mktemp -d)"
STORAGE_ROOT="$WORKDIR/storage"
CADDYFILE="$WORKDIR/Caddyfile"
CADDY_BIN="$WORKDIR/caddy"
CADDY_LOG="$WORKDIR/caddy.log"
mkdir -p "$STORAGE_ROOT"

# --- cleanup on exit (success or failure) ---
CADDY_PID=""
cleanup() {
  if [[ -n "$CADDY_PID" ]] && kill -0 "$CADDY_PID" 2>/dev/null; then
    kill "$CADDY_PID" 2>/dev/null || true
    wait "$CADDY_PID" 2>/dev/null || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# --- write the Caddyfile ---
cat > "$CADDYFILE" <<EOF
{
  storage permissive_file_storage {
    root "$STORAGE_ROOT"
  }
  admin off
  http_port $HTTP_PORT
  https_port $HTTPS_PORT
}

localhost {
  tls internal
  respond "ok" 200
}
EOF

# --- build caddy with the local plugin ---
echo "==> Building Caddy $CADDY_VERSION with local plugin..."
xcaddy build "$CADDY_VERSION" \
  --with "$PLUGIN_MODULE=." \
  --output "$CADDY_BIN" 2>&1 | sed 's/^/    /'

# --- start caddy ---
echo "==> Starting Caddy..."
"$CADDY_BIN" run --config "$CADDYFILE" --adapter caddyfile >"$CADDY_LOG" 2>&1 &
CADDY_PID=$!

# --- readiness: process must stay alive past a grace period ---
# (Caddy exits non-zero on config parse failure, so survival == ready)
sleep 2
if ! kill -0 "$CADDY_PID" 2>/dev/null; then
  echo "FAIL: Caddy exited during startup. Log:" >&2
  cat "$CADDY_LOG" >&2
  exit 1
fi

# --- trigger cert issuance via HTTPS request ---
echo "==> Triggering cert issuance..."
# Retry a few times; issuance can take a moment after first request.
for i in 1 2 3 4 5; do
  if curl -sk "https://localhost:$HTTPS_PORT/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# --- poll for the cert and key files to appear (issuance signal) ---
echo "==> Waiting for cert and key to be written to storage..."
CERT_FILE="$STORAGE_ROOT/certificates/local/localhost/localhost.crt"
KEY_FILE="$STORAGE_ROOT/certificates/local/localhost/localhost.key"
for i in $(seq 1 20); do
  if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
    break
  fi
  sleep 0.5
done
if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
  echo "FAIL: cert or key file not written: $CERT_FILE / $KEY_FILE" >&2
  echo "--- Caddy log ---" >&2
  cat "$CADDY_LOG" >&2
  echo "--- storage tree ---" >&2
  find "$STORAGE_ROOT" -print >&2 || true
  exit 1
fi

# --- assert permissions ---
# Every regular file (excluding locks/) must be 0644.
# Every directory  (excluding locks/) must be 0755.
# locks/ is created by certmagic's Lock() at 0700, bypassing our Store() override.
echo "==> Asserting permissions..."

bad_files=$(find "$STORAGE_ROOT" -type f -not -path "*/locks/*" ! -perm 0644)
if [[ -n "$bad_files" ]]; then
  echo "FAIL: files with wrong permissions (expected 0644):" >&2
  echo "$bad_files" | sed 's/^/    /' >&2
  echo "--- details ---" >&2
  echo "$bad_files" | xargs -r ls -la >&2
  exit 1
fi

bad_dirs=$(find "$STORAGE_ROOT" -type d -not -path "*/locks" -not -path "*/locks/*" ! -perm 0755)
if [[ -n "$bad_dirs" ]]; then
  echo "FAIL: directories with wrong permissions (expected 0755):" >&2
  echo "$bad_dirs" | sed 's/^/    /' >&2
  echo "--- details ---" >&2
  echo "$bad_dirs" | xargs -r ls -ld >&2
  exit 1
fi

echo "PASS: all files 0644, all dirs 0755 (excluding locks/)"
echo "==> E2E test passed."
