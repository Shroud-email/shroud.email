#!/bin/sh
set -eu

echo "Waiting for Caddy's first certificate..."
until /etc/periodic/daily/bundle_certs; do
  sleep 5
done

touch /tmp/startup-sync-complete
exec crond -f -l 0
