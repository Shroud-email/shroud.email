FROM alpine:3.15

RUN apk update && \
    apk add --no-cache bash openssl

WORKDIR /workdir

COPY bundle_certs.sh /etc/periodic/daily/bundle_certs

RUN chmod +x /etc/periodic/daily/bundle_certs

VOLUME /pem

CMD ["crond", "-f", "-l", "0"]
