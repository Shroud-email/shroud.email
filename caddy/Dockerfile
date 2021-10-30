# Compile caddy with custom modules
FROM caddy:2.4.5-builder as builder

ENV GOPRIVATE=gitlab.com/shroud/caddy-permissive-file-storage
RUN xcaddy build \
    --with gitlab.com/shroud/caddy-permissive-file-storage@v0.1.3

# Production image
FROM caddy:2.4.5-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
