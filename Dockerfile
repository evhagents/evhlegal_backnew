# Multi-stage Dockerfile for Phoenix (Elixir 1.18 / Erlang 28) with Tailwind v4 & esbuild

############################
# Build stage
############################
FROM elixir:1.18-slim AS build

ENV MIX_ENV=prod \
    LANG=C.UTF-8

# Install Node.js 20+ and other build dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       git \
       curl \
       ca-certificates \
       libstdc++6 \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex/rebar (no prompts)
RUN mix local.hex --force && mix local.rebar --force

# Cache deps by copying only mix files + config first
COPY mix.exs mix.lock ./
COPY config ./config

RUN mix deps.get --only prod

# Copy app code
COPY lib ./lib
COPY priv ./priv
COPY assets ./assets

# Install JS deps now that deps/ is available
RUN cd assets && npm install --no-audit --no-fund

# Build assets (downloads tool binaries as needed)
RUN mix assets.setup \
    && mix assets.deploy \
    && mix compile

# Generate the release
RUN mix release

############################
# Runtime stage
############################
FROM debian:bookworm-slim AS runtime

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    PHX_SERVER=true \
    PORT=4000

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       openssl \
       ca-certificates \
       curl \
       libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && adduser --system --no-create-home --group app

WORKDIR /app

# Copy release from build image
COPY --from=build /app/_build/prod/rel/evhlegalchat ./

USER app

EXPOSE 4000

# The release expects SECRET_KEY_BASE and DATABASE_URL at runtime
CMD ["/app/bin/evhlegalchat", "start"]
