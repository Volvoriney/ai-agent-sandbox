# Tasks: build-agent-sandbox

## 1. Recon and scaffolding (~15 min)

- [x] 1.1 Clone both upstream repos; pin to latest stable tag/commit and record the pins
- [x] 1.2 Read both projects' existing Docker configs (eShopOnWeb `docker-compose.yml`, Medplum `docker-compose.yml` and published images); note gaps vs. our requirements
- [x] 1.3 Create repo layout: `docker/`, `scripts/`, `results/`, `README.md` skeleton

## 2. eShopOnWeb sandbox (~40 min) — get fully green first

- [x] 2.1 Write `docker/compose.eshop.yml`: SQL Server (ACCEPT_EULA=Y, mem_limit 2.5g, healthcheck with start_period) + app/build container on an internal network
- [x] 2.2 Build base image with SDK and pre-restored NuGet packages (layer keyed on csproj/lockfiles)
- [x] 2.3 Write eShop runner stages: build → EF migrations + seed → start app → HTTP health check → `dotnet test --logger trx`
- [x] 2.4 Verify full pass end-to-end; capture evidence (results.json, screenshot/curl of HTTP response, test summary)

## 3. Medplum sandbox (~40 min)

- [x] 3.1 Write `docker/compose.medplum.yml`: PostgreSQL + Redis + server container, internal network, resource limits
- [x] 3.2 Build base image with Node and pre-installed dependencies (`npm ci` layer keyed on package-lock)
- [x] 3.3 Write Medplum runner stages: build → start server (migrations auto-run) → `/healthcheck` probe → tests with JSON reporter; time the test suite and cut to server package if over budget (record the cut in results)
- [x] 3.4 Verify end-to-end; capture evidence

## 4. Unified lifecycle and output capture (~15 min)

- [x] 4.1 Write top-level `sandbox.ps1` + `sandbox.sh` with `up|run|reset|down <project>`; `reset` = `compose down -v && up` (no image rebuild)
- [x] 4.2 Implement `results/<run-id>/results.json` writer: per-stage status/duration/exit code, overall result, skipped stages on failure; bind-mount results dir to host
- [x] 4.3 Confirm isolation: cross-composition network test, non-root check, `docker inspect` for limits

## 5. Documentation and deliverables (~10 min)

- [x] 5.1 README: architecture decisions (two compositions, native DBs, layered images + ephemeral volumes), startup-time strategy, security/isolation limits and next steps, resource budget
- [x] 5.2 README: AI-usage notes — what the agent got right/wrong, where intervention was needed (required by the brief)
- [x] 5.3 Collect proof-it-works evidence into the repo (docs/proof-of-work.md); outline the 15–20 min walkthrough (docs/walkthrough.md). NOTE: push to GitHub left to the user (no remote configured / authorization needed)
