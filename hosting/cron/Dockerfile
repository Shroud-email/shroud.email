FROM alpine:3.15

RUN apk update && \
    apk add --no-cache bash

WORKDIR /workdir

COPY lets-encrypt-r4.pem /workdir/lets-encrypt-r4.pem
COPY bundle_certs.sh /etc/periodic/daily/bundle_certs

RUN chmod +x /etc/periodic/daily/bundle_certs

VOLUME /pem

CMD ["crond", "-f", "-l", "0"]
