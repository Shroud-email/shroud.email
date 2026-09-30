#!/bin/sh
set -e

DOMAIN="$1"
SELECTOR="shroudemail"

usage()
{
    echo "   usage: ${0} <example.com>" 2>&1
    echo 2>&1
    exit 1
}

if [ -z "$DOMAIN" ]; then
    usage
fi

# Create a directory for each DKIM signing domain
mkdir -p "$DOMAIN"
cd "$DOMAIN" || exit

# The selector can be any value that is a valid DNS label
echo $SELECTOR > selector

# Generate private and public keys
openssl genrsa -out private 2048
chmod 0400 private
openssl rsa -in private -out public -pubout

DNS_NAME="${SELECTOR}._domainkey"
DNS_ADDRESS="v=DKIM1;p=$(grep -v '^-' public | tr -d '\n')"

# Make it really easy to publish the public key in DNS
# by creating a file named 'dns', with instructions
cat > dns <<EO_DKIM_DNS
Add this TXT record to the ${DOMAIN} DNS zone.

${DNS_NAME}    IN   TXT   ${DNS_ADDRESS}
EO_DKIM_DNS

cd ..
