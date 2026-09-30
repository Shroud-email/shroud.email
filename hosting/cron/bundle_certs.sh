#!/bin/bash
set -e

if [ -z "$EMAIL_DOMAIN" ]; then echo "EMAIL_DOMAIN is not set"; exit 1; fi

cd /workdir
echo "Copying Caddy certs to Haraka..."
cd "/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$EMAIL_DOMAIN"
cp "${EMAIL_DOMAIN}.key" /pem/tls_key.pem
cat "${EMAIL_DOMAIN}.crt" /workdir/lets-encrypt-r4.pem > /pem/tls_cert.pem
echo "Copied Caddy certs to Haraka."