FROM alpine:3.15

RUN apk update && \
    apk add --no-cache bash openssl

WORKDIR /workdir

COPY bundle_certs.sh /workdir/bundle_certs.sh
COPY crontab /etc/crontabs/root

RUN chmod +x /workdir/bundle_certs.sh

VOLUME /pem

CMD ["sh", "-c", "/workdir/bundle_certs.sh && exec crond -f -l 0"]
