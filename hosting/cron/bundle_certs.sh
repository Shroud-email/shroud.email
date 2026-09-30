#!/bin/bash
set -eo pipefail

if [ -z "$EMAIL_DOMAIN" ]; then echo "EMAIL_DOMAIN is not set"; exit 1; fi

echo "Copying Caddy certs to Haraka..."
CADDY_CERT_DIR="/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$EMAIL_DOMAIN"
PEM_DIR="/pem"
TLS_CONFIG="/haraka-config/tls.ini"

stage_dir=$(mktemp -d "$PEM_DIR/.tls-stage.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT

# Caddy may replace the key and certificate files separately during renewal.
# Snapshot both, then only publish them if they form a parseable matching pair.
cp "$CADDY_CERT_DIR/${EMAIL_DOMAIN}.key" "$stage_dir/tls_key.pem"
cp "$CADDY_CERT_DIR/${EMAIL_DOMAIN}.crt" "$stage_dir/tls_cert.pem"

openssl pkey -in "$stage_dir/tls_key.pem" -noout >/dev/null 2>&1
openssl x509 -in "$stage_dir/tls_cert.pem" -noout >/dev/null 2>&1

key_public=$(openssl pkey -in "$stage_dir/tls_key.pem" -pubout -outform DER 2>/dev/null | openssl dgst -sha256)
cert_public=$(openssl x509 -in "$stage_dir/tls_cert.pem" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256)

if [ "$key_public" != "$cert_public" ]; then
  echo "Caddy certificate and private key do not match; keeping the current Haraka certificate." >&2
  exit 1
fi

mv "$stage_dir/tls_key.pem" "$PEM_DIR/tls_key.pem"
mv "$stage_dir/tls_cert.pem" "$PEM_DIR/tls_cert.pem"
touch "$TLS_CONFIG"
echo "Copied Caddy certs to Haraka."
