# Compile caddy with custom modules
FROM caddy:2.4.5-builder as builder

ENV GOPRIVATE=github.com/Shroud-email/caddy-permissive-file-storage
RUN xcaddy build \
    --with github.com/Shroud-email/caddy-permissive-file-storage@v0.1.4

# Production image
FROM caddy:2.4.5-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
