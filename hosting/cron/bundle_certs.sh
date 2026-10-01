#!/bin/bash
set -euo pipefail

if [ -z "${EMAIL_DOMAIN:-}" ]; then echo "EMAIL_DOMAIN is not set"; exit 1; fi

cd /workdir
echo "Copying Caddy certs to Haraka..."
cd "/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$EMAIL_DOMAIN"
# Publish one complete pair so Haraka cannot reload a new key with an old cert.
umask 077
bundle=$(mktemp /pem/.tls.pem.XXXXXX)
trap 'rm -f "$bundle" "${bundle}.cert.pub" "${bundle}.key.pub"' EXIT
# Caddy's .crt already contains the issued certificate chain.
cat "${EMAIL_DOMAIN}.key" "${EMAIL_DOMAIN}.crt" > "$bundle"
# Check the pair before replacing the last working bundle.
openssl x509 -in "$bundle" -checkend 0 -noout
openssl x509 -in "$bundle" -pubkey -noout > "${bundle}.cert.pub"
openssl pkey -in "$bundle" -pubout > "${bundle}.key.pub"
cmp "${bundle}.cert.pub" "${bundle}.key.pub"
mv "$bundle" /pem/tls.pem
echo "Copied Caddy certs to Haraka."
