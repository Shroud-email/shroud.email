#!/bin/bash
set -euo pipefail

if [ -z "$EMAIL_DOMAIN" ]; then echo "EMAIL_DOMAIN is not set"; exit 1; fi

cert_dir="/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$EMAIL_DOMAIN"
key="$cert_dir/$EMAIL_DOMAIN.key"
cert="$cert_dir/$EMAIL_DOMAIN.crt"

# On a fresh deployment Caddy may still be completing ACME. Retry next minute.
if [[ ! -s "$key" || ! -s "$cert" ]]; then
  echo "Waiting for Caddy's certificate for $EMAIL_DOMAIN..."
  exit 0
fi

if cmp -s "$key" /pem/tls_key.pem && cmp -s "$cert" /pem/tls_cert.pem; then
  exit 0
fi

# Stage and validate a complete matching pair before triggering Haraka's reload.
# Caddy's .crt already contains the chain; do not append a fixed intermediate.
trap 'rm -f /pem/tls_key.pem.tmp /pem/tls_cert.pem.tmp' EXIT
cp "$key" /pem/tls_key.pem.tmp
cp "$cert" /pem/tls_cert.pem.tmp
openssl x509 -in /pem/tls_cert.pem.tmp -noout -checkend 0
cert_public_key=$(openssl x509 -in /pem/tls_cert.pem.tmp -pubkey -noout)
key_public_key=$(openssl pkey -in /pem/tls_key.pem.tmp -pubout)
if [[ "$cert_public_key" != "$key_public_key" ]]; then
  echo "Caddy certificate and private key do not match; keeping existing Haraka certs." >&2
  exit 1
fi

chmod 600 /pem/tls_key.pem.tmp
chmod 644 /pem/tls_cert.pem.tmp
mv /pem/tls_key.pem.tmp /pem/tls_key.pem
mv /pem/tls_cert.pem.tmp /pem/tls_cert.pem
touch /haraka-config/tls.ini
echo "Copied Caddy certs and triggered Haraka TLS reload."
