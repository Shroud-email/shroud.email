FROM alpine:3.15

RUN apk update && \
    apk add --no-cache bash openssl

WORKDIR /workdir

COPY bundle_certs.sh /etc/periodic/daily/bundle_certs
COPY start.sh /usr/local/bin/start

RUN chmod +x /etc/periodic/daily/bundle_certs /usr/local/bin/start

VOLUME /pem

HEALTHCHECK --interval=5s --timeout=2s --retries=60 \
    CMD test -f /tmp/startup-sync-complete && test -s /pem/tls_key.pem && test -s /pem/tls_cert.pem

CMD ["/usr/local/bin/start"]
