# Compile Caddy with custom modules.
#   - caddy-permissive-file-storage: world-readable certs so the cron
#     sidecar can bundle them for Haraka (the whole reason this fork exists).
#   - caddy-dns/bunny: DNS-01 ACME via Bunny.net, opt-in via Caddyfile.bunny.
FROM caddy:2.10-builder AS builder

RUN xcaddy build v2.10.0 \
    --with github.com/Shroud-email/caddy-permissive-file-storage@main \
    --with github.com/caddy-dns/bunny@v1.2.0

# Production image
FROM caddy:2.10-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
