# syntax=docker/dockerfile:1
#
# Medplum sandbox base image: Node 22 + full monorepo + pre-installed deps + pre-built server.
#
# Unlike eShop (small source, bind-mounted per run), Medplum is a large npm-workspaces +
# Turborepo monorepo. Manifest-only copying is impractical across ~40 workspaces, so we bake
# the whole source + `npm ci` + the server build into the image. The heavy work runs ONCE and
# is cached; per-run clean state comes from a fresh container's copy-on-write layer (design D3).
#
# Node version satisfies the repo's engines: "^22.18.0 || >=24.2.0".

FROM node:22-bookworm AS base

ENV NODE_ENV=development \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false

WORKDIR /usr/src/medplum

# Build context is the pinned upstream checkout (.upstream/medplum). Its .dockerignore
# already excludes .git/node_modules/dist, so this copies source only.
COPY . .

# Install all workspace dependencies (dev included — required to build and to run jest).
RUN npm ci

# Build only the server and its workspace dependencies; Turborepo prunes the task graph
# so we don't build the React app, docs, or examples (out of scope for the server sandbox).
RUN npx turbo run build --filter=@medplum/server

# curl for the runner's HTTP /healthcheck stage.
RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

# The bind-mounted working copy is owned by the host user, not the container's root; without
# this git refuses with "dubious ownership". Allow git to operate on the mounted repo.
RUN git config --system --add safe.directory '*'

# Idle by default; sandbox.sh exec's the bind-mounted runner into this container.
CMD ["sleep", "infinity"]
