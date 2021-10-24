ARG MIX_ENV="prod"

FROM hexpm/elixir:1.12.3-erlang-24.1.2-alpine-3.14.2 as build

# install build dependencies
RUN apk add --no-cache build-base git python3 curl

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ARG MIX_ENV
ENV MIX_ENV="${MIX_ENV}"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/$MIX_ENV.exs config/
RUN mix deps.compile

COPY priv priv

# note: if your project uses a tool like https://purgecss.com/,
# which customizes asset compilation based on what it finds in
# your Elixir templates, you will need to move the asset compilation
# step down so that `lib` is available.
COPY assets assets
RUN mix assets.deploy

# compile and build the release
COPY lib lib
RUN mix compile
# changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/
# uncomment COPY if rel/ exists
# COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM alpine:3.14.2 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs

ARG MIX_ENV
ENV USER="elixir"

WORKDIR "/home/${USER}/app"
# Creates an unprivileged user to be used exclusively to run the Phoenix app
RUN \
  addgroup \
   -g 1000 \
   -S "${USER}" \
  && adduser \
   -s /bin/sh \
   -u 1000 \
   -G "${USER}" \
   -h "/home/${USER}" \
   -D "${USER}" \
  && su "${USER}"

# Everything from this line onwards will run in the context of the unprivileged user.
USER "${USER}"

COPY CHECKS ./
COPY scripts/entrypoint.sh ./
COPY --from=build --chown="${USER}":"${USER}" /app/_build/"${MIX_ENV}"/rel/shroud ./

ENTRYPOINT ["./entrypoint.sh"]
# Expose web (8080) and SMTP (2525)
ENV PORT=8080
EXPOSE 8080
EXPOSE 2525

# Usage:
#  * build: sudo docker image build -t elixir/shroud .
#  * shell: sudo docker container run --rm -it --entrypoint "" -p 127.0.0.1:4000:4000 elixir/shroud sh
#  * run:   sudo docker container run --rm -it -p 127.0.0.1:4000:4000 --name shroud elixir/shroud
#  * exec:  sudo docker container exec -it shroud sh
#  * logs:  sudo docker container logs --follow --tail 100 shroud
CMD ["start"]
