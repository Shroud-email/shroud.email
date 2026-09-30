#!/bin/bash
set -euo pipefail

if [ -z "${EMAIL_DOMAIN:-}" ]; then echo "EMAIL_DOMAIN is not set"; exit 1; fi

# Serialize cron/manual syncs across the shared volume, including publication.
exec 9>/pem/.sync.lock
flock -n 9 || exit 0

cert_dir="/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$EMAIL_DOMAIN"
key="$cert_dir/$EMAIL_DOMAIN.key"
cert="$cert_dir/$EMAIL_DOMAIN.crt"

# On a fresh deployment Caddy may still be completing ACME. Retry next minute.
if [[ ! -s "$key" || ! -s "$cert" ]]; then
  echo "Waiting for Caddy's certificate for $EMAIL_DOMAIN..."
  exit 0
fi

if cmp -s "$key" /pem/current/tls_key.pem && cmp -s "$cert" /pem/current/tls_cert.pem; then
  # Recover a sync interrupted after publication but before the reload trigger.
  if [[ /pem/current -nt /haraka-config/tls.ini ]]; then touch /haraka-config/tls.ini; fi
  exit 0
fi

# Stage and validate a complete matching pair before triggering Haraka's reload.
# Caddy's .crt already contains the chain; do not append a fixed intermediate.
pair_dir=$(mktemp -d /pem/pair.XXXXXX)
trap 'if [[ ! /pem/current -ef "$pair_dir" ]]; then rm -rf "$pair_dir"; fi; rm -f /pem/current.tmp' EXIT
cp "$key" "$pair_dir/tls_key.pem"
cp "$cert" "$pair_dir/tls_cert.pem"
openssl x509 -in "$pair_dir/tls_cert.pem" -noout -checkend 0
cert_public_key=$(openssl x509 -in "$pair_dir/tls_cert.pem" -pubkey -noout)
key_public_key=$(openssl pkey -in "$pair_dir/tls_key.pem" -pubout)
if [[ "$cert_public_key" != "$key_public_key" ]]; then
  echo "Caddy certificate and private key do not match; keeping existing Haraka certs." >&2
  exit 1
fi

chmod 600 "$pair_dir/tls_key.pem"
chmod 644 "$pair_dir/tls_cert.pem"
# A relative symlink works at both /pem and Haraka's config/certs mount.
# Keep previous versions intact so in-flight readers can finish safely.
ln -s "$(basename "$pair_dir")" /pem/current.tmp
mv -Tf /pem/current.tmp /pem/current
touch /haraka-config/tls.ini
echo "Copied Caddy certs and triggered Haraka TLS reload."
