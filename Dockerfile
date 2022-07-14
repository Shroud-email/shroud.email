ARG MIX_ENV="prod"

FROM hexpm/elixir:1.13.2-erlang-24.1.7-debian-bullseye-20210902-slim as build

# install build dependencies
RUN apt-get update && apt-get install -y build-essential git curl npm cargo

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
COPY config/config.exs config/appsignal.exs config/$MIX_ENV.exs config/
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib
RUN npm --prefix assets ci
# compile and build the release
RUN mix compile
RUN mix assets.deploy

# changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/
# uncomment COPY if rel/ exists
# COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM hexpm/elixir:1.13.2-erlang-24.1.7-debian-bullseye-20210902-slim as app
RUN apt-get update && apt-get install -y openssl libncurses6

ARG MIX_ENV
ENV USER="elixir"

WORKDIR "/home/${USER}/app"
# Creates an unprivileged user to be used exclusively to run the Phoenix app
RUN \
  addgroup \
   --gid 1000 \
   "${USER}" \
  && adduser \
   --shell /bin/sh \
   --uid 1000 \
   --ingroup "${USER}" \
   --home "/home/${USER}" \
   "${USER}" \
  && su "${USER}"

# Everything from this line onwards will run in the context of the unprivileged user.
USER "${USER}"

COPY scripts/entrypoint.sh ./
COPY --from=build --chown="${USER}":"${USER}" /app/_build/"${MIX_ENV}"/rel/shroud ./

ENTRYPOINT ["./entrypoint.sh"]
# Expose web (8080) and SMTP-with-STARTTLS (1587)
ENV PORT=8080
EXPOSE 8080
EXPOSE 1587

# Usage:
#  * build: sudo docker image build -t elixir/shroud .
#  * shell: sudo docker container run --rm -it --entrypoint "" -p 127.0.0.1:4000:4000 elixir/shroud sh
#  * run:   sudo docker container run --rm -it -p 127.0.0.1:4000:4000 --name shroud elixir/shroud
#  * exec:  sudo docker container exec -it shroud sh
#  * logs:  sudo docker container logs --follow --tail 100 shroud
CMD ["start"]
