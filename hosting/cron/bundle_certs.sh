#!/bin/bash
set -eo pipefail

if [ -z "$EMAIL_DOMAIN" ]; then echo "EMAIL_DOMAIN is not set"; exit 1; fi

echo "Copying Caddy certs to Haraka..."
CADDY_CERT_DIR="${CADDY_CERT_DIR:-/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$EMAIL_DOMAIN}"
PEM_DIR="${PEM_DIR:-/pem}"
TLS_CONFIG="${TLS_CONFIG:-/haraka-config/tls.ini}"
VERSIONS_DIR="$PEM_DIR/versions"

mkdir -p "$VERSIONS_DIR"
# Serialize the complete sync. In particular, a publisher must not prune using
# a current version that another run has replaced while this run was copying.
exec 9>"$PEM_DIR/.bundle_certs.lock"
flock 9
version_dir=$(mktemp -d "$VERSIONS_DIR/tls.XXXXXX")
next_link="$PEM_DIR/.current.$$"
version_name() {
  case "$1" in
    versions/*/*|versions/) return 1 ;;
    versions/*) printf '%s\n' "${1#versions/}" ;;
    *) return 1 ;;
  esac
}
prune_versions() {
  active=$1
  previous=$2
  if [ -z "$previous" ]; then
    for candidate in "$VERSIONS_DIR"/*; do
      [ -d "$candidate" ] || continue
      [ "${candidate##*/}" = "$active" ] && continue
      if [ -z "$previous" ] || [ "$candidate" -nt "$VERSIONS_DIR/$previous" ]; then
        previous=${candidate##*/}
      fi
    done
  fi
  for candidate in "$VERSIONS_DIR"/*; do
    [ -d "$candidate" ] || continue
    candidate=${candidate##*/}
    [ "$candidate" = "$active" ] || [ "$candidate" = "$previous" ] ||
      rm -rf "$VERSIONS_DIR/$candidate"
  done
}
cleanup() {
  # An interruption immediately after rename must not remove the active version.
  if [ -n "$version_dir" ] &&
    [ "$(readlink "$PEM_DIR/current" || true)" != "versions/${version_dir##*/}" ]; then
    rm -rf "$version_dir"
  fi
  rm -f "$next_link"
}
trap cleanup EXIT

# Caddy may replace the key and certificate files separately during renewal.
# Snapshot both, then only publish them if they form a parseable matching pair.
cp "$CADDY_CERT_DIR/${EMAIL_DOMAIN}.key" "$version_dir/tls_key.pem"
cp "$CADDY_CERT_DIR/${EMAIL_DOMAIN}.crt" "$version_dir/tls_cert.pem"

openssl pkey -in "$version_dir/tls_key.pem" -noout >/dev/null 2>&1
openssl x509 -in "$version_dir/tls_cert.pem" -noout >/dev/null 2>&1

key_public=$(openssl pkey -in "$version_dir/tls_key.pem" -pubout -outform DER 2>/dev/null | openssl dgst -sha256)
cert_public=$(openssl x509 -in "$version_dir/tls_cert.pem" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256)

if [ "$key_public" != "$cert_public" ]; then
  echo "Caddy certificate and private key do not match; keeping the current Haraka certificate." >&2
  exit 1
fi

current_link=$(readlink "$PEM_DIR/current" || true)
current_version=$(version_name "$current_link" || true)
if [ -n "$current_version" ] &&
  cmp -s "$version_dir/tls_key.pem" "$PEM_DIR/current/tls_key.pem" &&
  cmp -s "$version_dir/tls_cert.pem" "$PEM_DIR/current/tls_cert.pem"; then
  rm -rf "$version_dir"
  version_dir=
  # Also recover a prior interruption between publication and the reload trigger.
  touch "$TLS_CONFIG"
  prune_versions "$current_version" ""
  echo "Caddy certs are unchanged; keeping the current Haraka certificate."
  exit 0
fi

# The temporary link and current live on the same filesystem. BusyBox mv -T uses
# rename(2), so readers see either the complete old version or the complete new one.
ln -s "versions/${version_dir##*/}" "$next_link"
mv -fT "$next_link" "$PEM_DIR/current"
active_version=${version_dir##*/}
version_dir=
touch "$TLS_CONFIG"
prune_versions "$active_version" "$current_version"
echo "Copied Caddy certs to Haraka."
