# Recon notes — upstream Docker configs and gaps

Captured 2026-06-14 from the pinned checkouts (`scripts/pins.env`). This is the
"what already exists / where are the gaps" pass the brief asks for.

## eShopOnWeb (`main` @ `5ad05cbe`)

**What ships upstream:**
- `docker-compose.yml` + `docker-compose.override.yml`: `eshopwebmvc` + `eshoppublicapi` + `sqlserver` (`mcr.microsoft.com/mssql/server:2022-latest`, `ACCEPT_EULA=Y`, `SA_PASSWORD=@someThingComplicated1234`).
- `src/Web/Dockerfile`: single build → publish → aspnet runtime.
- App listens on `:8080` (`ASPNETCORE_URLS=http://+:8080`, env `Docker`); `appsettings.Docker.json` connection strings point at `sqlserver,1433` with SA auth.
- `Program.cs` calls `await app.SeedDatabaseAsync()` → **EF migrations + seed run automatically at app startup** (seed is app-side, not EF-seed).
- Tests: `tests/UnitTests`, `tests/IntegrationTests`, `tests/FunctionalTests`, `tests/PublicApiIntegrationTests`.

**Gaps vs. our requirements:**
1. **Stale SDK** — `global.json` pins **.NET SDK 10.0.0** but `src/Web/Dockerfile` uses `sdk:9.0`. Building with 9.0 fails the `global.json` floor. → use `sdk:10.0`.
2. **No layer caching** — Dockerfile does `COPY . .` before `dotnet restore`, so any source edit busts the restore. → split manifest copy + `restore` into a cached layer (D3).
3. **Host-coupled / interactive** — override mounts `~/.aspnet/https` and `~/.microsoft/usersecrets` from the host. Not headless-safe. → drop; use HTTP-only in-sandbox.
4. **No healthcheck, no resource limits, no test stage, no isolation** — all added by us.
5. Hardcoded SA password in compose. → keep dev-only, parameterized via env, documented as non-secret sandbox credential.

## Medplum (`v5.1.9`)

**What ships upstream:**
- `docker-compose.yml`: `postgres:16` (`POSTGRES_USER/PASSWORD=medplum`, init dir `./postgres/`) + `redis:7` (`--requirepass medplum`).
- Root `Dockerfile`: **production** image built from prebuilt tarballs (`scripts/build-docker-server.sh`) on hardened `dhi.io/node` images — needs DockerHub repo env + a prior build step. Not directly source-buildable.
- `packages/server` scripts: `build` (`tsc && build.mjs`), `test` (`jest`), `migrate` (`tsx src/migrations/migrate-main.ts`), `start` (`node dist/index.js`).
- Config via `packages/server/medplum.config.json` (loader supports `file:`/`env:`); `/healthcheck` endpoint in `packages/server/src/healthcheck.ts`.
- Node engines: `^22.18.0 || >=24.2.0`. Monorepo built with npm workspaces + Turborepo.

**Gaps vs. our requirements:**
1. **Production Dockerfile unusable as-is** — depends on a tarball build script and DockerHub. → build the server **from source in the monorepo** (`npm ci` at root → build `core` deps → build `server`).
2. **`npm ci` not cached on lockfile** — must structure our base image to key the install on `package-lock.json` (D3).
3. **Config points at localhost** — `medplum.config.json` assumes local pg/redis. → provide a sandbox config pointing at the composition's `postgres`/`redis` service names.
4. **Full monorepo test suite is large** — budget risk. → run the **server package** tests with a JSON reporter; record any scope cut in `results.json` (spec project-medplum).
5. **No resource limits / network isolation** in upstream compose. → added by us.

## Shared design implications
- Two isolated compositions (one compose file each) — confirmed appropriate: zero shared services, conflicting DB engines (D1).
- Native DBs per project; no consolidation (D2).
- Migrate+seed timing differs: eShop couples them to **app startup**; Medplum runs migrations on **server startup**. Both are captured by the `start` stage + verified by `healthcheck`.
