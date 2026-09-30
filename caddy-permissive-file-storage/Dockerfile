# Compile caddy with custom modules
# Uses a recent Caddy builder image (Go 1.24+ toolchain)
FROM caddy:2.10-builder AS builder

COPY . /src
RUN xcaddy build v2.10.0 \
    --with github.com/Shroud-email/caddy-permissive-file-storage=/src

# Production image
FROM caddy:2.10-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
VOLUME /etc/caddy/Caddyfile
