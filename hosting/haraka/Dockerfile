FROM node:24-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1

RUN apk add --no-cache python3 make g++ tini openssl
ENV NODE_ENV=production

WORKDIR /app
# Keep dependencies outside the Compose bind mount at /app/haraka_config.
COPY ./haraka_config/package.json ./haraka_config/package-lock.json ./
RUN npm ci --omit=dev --omit=optional
COPY ./haraka_config /app/haraka_config
RUN node --test haraka_config/test/*.test.js

ENTRYPOINT ["/sbin/tini", "--", "/app/node_modules/.bin/haraka", "-c", "/app/haraka_config"]
