#!/usr/bin/env bash
# Local Docker smoke tests; no public DNS, ACME requests or production writes.
set -euo pipefail
hosting=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
container="shroud-hosting-test-$$"
cleanup() {
  if [[ "$?" != 0 ]]; then docker logs "$container" >&2 2>/dev/null || true; fi
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap cleanup EXIT

docker build -t shroud-haraka:test "$hosting/haraka"
docker build -t shroud-cron:test "$hosting/cron"
docker build -t shroud-caddy:test -f "$hosting/caddy/Dockerfile" "$hosting/.."

docker compose --project-directory "$hosting" --env-file "$hosting/example.env" config --services > "$scratch/services"
if grep -Ex 'cap|valkey' "$scratch/services"; then
  echo "Cap services enabled by default!"; exit 1
fi
docker compose --project-directory "$hosting" --env-file "$hosting/example.env" --profile cap config --services > "$scratch/services"
grep -qx cap "$scratch/services"
grep -qx valkey "$scratch/services"

for caddyfile in Caddyfile Caddyfile.bunny; do
  for capfile in disabled.caddy http.caddy bunny.caddy; do
    domain=cap.example.com
    [[ "$capfile" != disabled.caddy ]] || domain=""
    docker run --rm -e ADMIN_EMAIL=admin@example.com -e APP_DOMAIN=app.example.com \
      -e EMAIL_DOMAIN=example.com -e BUNNY_API_KEY=test -e "CAP_DOMAIN=$domain" \
      -e "CAP_CADDYFILE=$capfile" -v "$hosting/caddy:/etc/caddy:ro" \
      shroud-caddy:test caddy adapt --config "/etc/caddy/$caddyfile" > "$scratch/caddy.json"
    python3 - "$scratch/caddy.json" "$capfile" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
serialized = json.dumps(config)
assert ('cap:3000' in serialized) == (sys.argv[2] != 'disabled.caddy')
assert 'disabled.localhost' not in serialized
PY
  done
done

mkdir -p "$scratch/caddy/certificates/acme-v02.api.letsencrypt.org-directory/example.com" "$scratch/pem"
cp -r "$hosting/haraka/haraka_config" "$scratch/haraka"
printf 'example.com\n' > "$scratch/haraka/config/me"
certdir="$scratch/caddy/certificates/acme-v02.api.letsencrypt.org-directory/example.com"
copy_certs() {
  docker run --rm --user "$(id -u):$(id -g)" -e EMAIL_DOMAIN=example.com \
    -v "$scratch/caddy:/caddy:ro" -v "$scratch/pem:/pem" \
    -v "$scratch/haraka/config:/haraka-config" \
    shroud-cron:test /workdir/bundle_certs.sh
}
copy_certs
[[ ! -e "$scratch/pem/tls_key.pem" ]]

docker run -d --name "$container" -p 127.0.0.1::25 \
  -e EMAIL_DOMAIN=example.com -e SMTP_USERNAME=test -e SMTP_PASSWORD=test \
  -e WITHOUT_CONFIG_CACHE=1 -v "$scratch/haraka:/app/haraka_config" \
  -v "$scratch/pem:/app/haraka_config/config/certs" shroud-haraka:test
port=$(docker port "$container" 25/tcp | cut -d: -f2)
check_smtp() {
  python3 - "$port" "$1" <<'PY'
import smtplib, ssl, sys, time
port, expected = int(sys.argv[1]), sys.argv[2]
deadline = time.monotonic() + 30
while True:
    try:
        with smtplib.SMTP('127.0.0.1', port, timeout=3) as smtp:
            smtp.ehlo('test.example.com')
            if expected == 'absent':
                assert not smtp.has_extn('starttls')
            else:
                smtp.starttls(context=ssl._create_unverified_context())
                actual = ssl.DER_cert_to_PEM_cert(smtp.sock.getpeercert(binary_form=True))
                assert actual.strip() == open(expected).read().strip()
        break
    except (OSError, smtplib.SMTPException, AssertionError):
        if time.monotonic() >= deadline:
            raise
        time.sleep(0.2)
PY
}
check_smtp absent
for generation in first renewed; do
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=example.com" \
    -keyout "$certdir/example.com.key" -out "$certdir/example.com.crt" 2>/dev/null
  copy_certs
  cmp "$certdir/example.com.key" "$scratch/pem/tls_key.pem"
  cmp "$certdir/example.com.crt" "$scratch/pem/tls_cert.pem"
  check_smtp "$certdir/example.com.crt"
done

# Mismatched or malformed certificates must not overwrite the working pair.
cp "$scratch/pem/tls_key.pem" "$scratch/good.key"
cp "$scratch/pem/tls_cert.pem" "$scratch/good.crt"
openssl genrsa -out "$certdir/example.com.key" 2048 2>/dev/null
if copy_certs; then echo "Accepted a mismatched key!"; exit 1; fi
printf 'not a certificate\n' > "$certdir/example.com.crt"
if copy_certs; then echo "Accepted a malformed certificate!"; exit 1; fi
cmp "$scratch/good.key" "$scratch/pem/tls_key.pem"
cmp "$scratch/good.crt" "$scratch/pem/tls_cert.pem"
check_smtp "$scratch/good.crt"
echo "Hosting smoke tests passed (profiles, Caddy, headers plugin, TLS issuance/renewal/rejection)."
