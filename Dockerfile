# ---- build args
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28
ARG BUILDER_IMAGE="elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

# ---- builder
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir -p config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.deploy

RUN mix compile
COPY config/runtime.exs config/
RUN mix release

# ---- runner
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN useradd -m appuser && chown appuser /app

ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=8080
EXPOSE 8080

COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/imaedge ./
COPY --chown=appuser:appuser sqlca.pem ./sqlca.pem

USER appuser

CMD ["/app/bin/imaedge", "start"]
