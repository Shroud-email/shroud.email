FROM node:18.4-alpine3.16

ARG version=2.8.28

RUN apk add --no-cache python3 make g++ tini openssl
ENV NODE_ENV production

WORKDIR /app
RUN npm install --global Haraka@${version} --unsafe
# This active plugin is only an optional Haraka dependency and may be skipped
# by npm. Install a version compatible with Haraka 2 explicitly.
RUN npm install --global haraka-plugin-headers@1.1.0
RUN npm install --global pg@8.7.3
COPY ./haraka_config /app/haraka_config

ENTRYPOINT ["/sbin/tini", "--", "haraka", "-c", "/app/haraka_config"]
