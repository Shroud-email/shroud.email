#!/bin/sh
set -eu

rm -f /tmp/startup-sync-complete

if [ -z "${EMAIL_DOMAIN:-}" ]; then
  echo "ERROR: EMAIL_DOMAIN is required; set it to the domain whose certificates should be bundled." >&2
  exit 1
fi

echo "Waiting for Caddy's first certificate..."
attempt=1
max_attempts=180
until /etc/periodic/daily/bundle_certs; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "ERROR: Initial certificate sync timed out after about 15 minutes. Check Caddy logs and DNS/ACME logs, then restart the cron service." >&2
    exit 1
  fi

  attempt=$((attempt + 1))
  sleep 5
done

touch /tmp/startup-sync-complete
exec crond -f -l 0
