# AI Agent Sandbox

A Docker-based, **non-interactive execution environment** an AI coding agent (or an
automated pipeline) uses to clone, build, migrate, run, health-check, and test real
projects — then collect structured results and tear down cleanly, hundreds of times a day.

This sandbox proves itself against two deliberately conflicting stacks:

| | eShopOnWeb | Medplum |
|---|---|---|
| Runtime | .NET 10 (ASP.NET Core) | Node.js (TypeScript) |
| Database | SQL Server | PostgreSQL + Redis |
| Build | dotnet CLI | npm / Turborepo |
| "Works" = | build + migrate + seed + HTTP + tests | build + start + migrate + `/healthcheck` + tests |

> It is the environment an AI harness runs *inside* — not the harness itself.

## Quick start

```bash
# one-time: clone pinned upstream sources into .upstream/
./sandbox.sh setup

# the agent loop: a persistent workspace the harness works INSIDE
./sandbox.sh up    <project>          # start workspace + backing services (idle, alive)
./sandbox.sh exec  <project> <cmd…>   # run a command in the live workspace (build/edit/test)
./sandbox.sh shell <project>          # interactive bash in the live workspace (poke around)
./sandbox.sh run   <project>          # exec the validation pipeline → results.json (the gate)
./sandbox.sh reset <project>          # clean state (no image rebuild)
./sandbox.sh down  <project>          # full teardown
```

Typical task: `up` → (`exec` build/test, `shell` to poke, iterate…) → `run` for the verdict →
`down`. Source is the **bind-mounted host clone**, so the agent's edits land directly in the
repo; `run` validates them and leaves the workspace up. `reset` resets **DB + deps** (source
hygiene is the harness's job via `git`). The **image** is built by `up` (not `run`) — re-run
`up` after a Dockerfile/dependency change. Results land in `results/<run-id>/` (`results.json`
verdict + `run.log` + native reports).

**Host support:** `sandbox.sh` is the single dispatcher — the production consumer is a Linux
CI pipeline. On **Windows**, run it from a **WSL2** shell (Docker Desktop already requires
WSL2; enable WSL integration for your distro). Git Bash is *not* supported (it mangles paths
before they reach `docker`). The container runners are Linux/bash regardless of host.

Compose host paths are anchored at **`${SANDBOX_ROOT}`** (the repo root), which the dispatcher
exports — so resolution is unambiguous and CWD-independent. A direct `docker compose -f …` must
export `SANDBOX_ROOT` first.

## Architecture

### Two isolated compositions, not one shared sandbox
Each project is one Docker Compose file (`docker/compose.eshop.yml`,
`docker/compose.medplum.yml`) with its own services, **private bridge network**, and
volumes. They share nothing. A thin dispatcher (`sandbox.ps1` / `sandbox.sh`) maps a
project name to its composition, so the consumer doesn't care that the internals differ.

*Why:* the stacks have conflicting DB engines and runtimes; an AI harness wants blast-radius
isolation (a poisoned eShop run can't touch Medplum) and the ability to spin each up/down
independently and in parallel. The rejected alternative — one mega-composition with both DB
engines always running — wastes ~3 GB RAM when an agent needs only one project and couples
their lifecycles.

**The generality lives in the structure, not a runtime abstraction.** Every project flows
through the *same five-stage contract* — `prepare/build → start → healthcheck → test` —
emitting the *same `results.json` schema*. Adding a third repo = one new `compose.X.yml`
plus one `run-checks.X` that fills those stages. The dispatcher and the result schema don't
change. Built for two; shaped to extend to N.

### Native databases per project — no consolidation
SQL Server for eShop, PostgreSQL + Redis for Medplum. eShop's EF Core migrations target SQL
Server; Medplum is deeply Postgres-specific. Porting either is out of budget and defeats
"test against reality." Schema isolation comes free from composition isolation.

### Startup performance — slow is allowed exactly once
Three times, only the first slow:

| Phase | Frequency | Strategy |
|---|---|---|
| Cold base-image build | once / on dep change | SDK or Node + restored deps baked into a layer |
| Warm spin-up per run | hundreds/day | fresh container from cached base + ephemeral DB |
| In-run iteration | many per run | incremental build; deps never re-fetched |

- **eShop**: multi-stage Dockerfile copies `Directory.Packages.props` + `global.json` +
  every `.csproj` *before* restoring, so the NuGet restore layer is keyed on project files.
  The `wasm-tools` workload + packages are baked, so per-run builds restore **offline** in
  seconds. Source is the **bind-mounted host clone** at `/work` (NuGet lives in `/nuget`,
  outside the source tree, so the mount can't shadow it).
- **Medplum**: the monorepo's ~40 npm workspaces are baked once (`npm ci` +
  `turbo build --filter=@medplum/server`). At runtime the **host clone is bind-mounted** at
  `/usr/src/medplum`, with an **anonymous volume preserving the baked `node_modules`** so the
  mount doesn't shadow deps; `turbo` rebuilds only changed packages.

### Clean state between runs — split ownership
Source comes from the **bind-mounted host clone** (a real git checkout), so an agent's edits
land directly in the repo and the **harness commits/pushes/opens the PR from the host** (creds
+ network stay outside the untrusted container). Clean-state ownership splits accordingly:
- **Source** → the **harness** (fresh per-task `git checkout` / `git clean` on the mount).
- **DB + deps** → the **sandbox**: `reset` = `down -v && up` (no `--build`) drops the DB
  volume **and** the `node_modules` anonymous volume, re-created from the cached image — seconds.

`git` works inside the workspace (`safe.directory` set, since the mount is host-owned), so the
agent can `diff`/`commit` directly — no `.git`-baking, no patch-export.

> Windows-via-WSL note: bind-mounting over `/mnt/c` is slower for the large Medplum tree;
> production is Linux (native bind, fast).

### Output capture — logs to stdout, structured verdict as an artifact
Logs and verdict are separate concerns with separate destinations:
- **Raw logs → stdout.** The runner (and the app it launches) write everything to
  stdout/stderr. `run` exec's the runner into the workspace, so that stream reaches the
  **dispatcher** (the exec client), which tees it to `results/<run-id>/run.log` — the local
  stand-in for the harness's log capture / aggregator (Loki/CloudWatch/Splunk) in production.
  The container manages **no logfiles** (12-factor). Capture happens *outside* the container,
  so logs survive even if the container dies mid-run.
- **Structured verdict → artifacts.** Written to the bind-mounted results dir:
  - **`results.json`** — per-stage `status`/`exitCode`/`durationSec`, skipped stages on
    failure, `overall`. A CI artifact (like JUnit/build output), not a log stream.
  - **native test reports** — TRX (`dotnet test`), jest JSON.

The dispatcher owns the guarantee: it reads the runner's exit code and, if `results.json` is
missing (runner died), **synthesizes a `"crashed"` envelope** so the consumer never gets
silence. Cheap consumers check the exit code; rich consumers read the JSON; the full log
stream is in `run.log` / the aggregator.

**Two consumers, two views of logs:**
- **Operator / platform (outside):** the stdout stream → `run.log` locally, → a log
  aggregator (Loki/CloudWatch/Splunk) in production.
- **AI agent (inside):** it **cannot** use `docker logs` (no host socket — isolation), so
  background processes (the app/server) `tee` to **files** the agent reads via exec:
  `results/latest/app.log` (eShop) / `results/latest/server.log` (Medplum). For its own
  foreground commands the agent just reads the exec stdout. `results/latest` is a stable
  symlink to the newest run so the agent needn't track run-ids:
  `./sandbox.sh exec <project> tail -f /results/latest/server.log`.

### Resource budget
Compose `mem_limit`/`cpus` on every container: SQL Server 2.5 GB, app/build 4 GB; Postgres
1 GB, Redis 512 MB, server 4 GB. Running one project at a time keeps the floor near ~6 GB;
both concurrently ~8 GB.

## Headless gotchas handled (non-interactive execution)
Real friction the sandbox absorbs so an agent never sees a prompt:
- **SQL Server EULA** → `ACCEPT_EULA=Y` env.
- **eShop SDK drift** → upstream Dockerfile pins `sdk:9.0` but `global.json` requires 10.0;
  we use `sdk:10.0`.
- **Blazor WASM** → `dotnet workload install wasm-tools` (else restore fails NETSDK1124).
- **Central MSBuild config** → `Directory.Packages.props` holds the TFM *and* package
  versions; it must be copied before restore.
- **HTTPS dev cert** → `launchSettings.json` forces `https://localhost:5001` needing a dev
  cert; we start with `--no-launch-profile` and bind HTTP-only via `ASPNETCORE_URLS`.
- **Aspire Seq telemetry** → `AddSeqEndpoint("seq")` throws without a `ServerUrl`; a dummy
  `ConnectionStrings__seq` satisfies startup (no Seq server runs).
- **Medplum test config** → `test.config.json` points at `localhost`; the runner repoints it
  at the composition's `postgres`/`redis` services.

## Security & isolation
- **Network**: each composition is on its own private bridge network. Cross-composition
  access is impossible (eShop can't reach Medplum's Postgres). Database ports are **not**
  published; only the app HTTP port is published, bound to `127.0.0.1`.
- **Host**: no Docker socket is mounted; the only host mounts are read-only source input and
  the `results/` output directory. Resource caps on every container limit blast radius.
- **Non-root**: SQL Server, Postgres, and Redis official images run as non-root. The .NET
  build/test container currently runs as **root** (SDK image default + bind-mount write
  needs) — documented here as a known limitation; running it as the image's `app` user is
  the next step.
- **Limits of this boundary**: a container is **not** a VM-grade boundary. For genuinely
  hostile agent-generated code, the next escalation is a microVM runtime (gVisor / Kata /
  Firecracker) plus seccomp/AppArmor profiles — out of scope for this exercise, named here
  as the production hardening path.

## How this was built with AI
This sandbox was built with Claude Code (Opus) — using an agent to build the environment
that agents run inside. Notes for the discussion the brief asks for:

**What the agent got right**
- Fast recon: cloned both repos, read their compose/Dockerfiles, and produced a gap analysis
  (`docs/recon-notes.md`) — including catching that eShop's upstream Dockerfile pins `sdk:9.0`
  while `global.json` requires 10.0.
- The architecture (two isolated compositions, five-stage contract, three-channel output
  capture, tiered DB model) held up end-to-end without rework.
- Generated the bulk of the Dockerfiles/compose/runner/dispatcher correctly on first pass.

**What needed iteration / intervention** (each is a real fix now in the repo)
- **Restore caching broke central config**: copying only `.csproj` files dropped
  `Directory.Packages.props` (which holds the TFM *and* package versions) → `NETSDK1124`.
  Had to copy the central props before restore.
- **Blazor WASM workload**: restore needed `dotnet workload install wasm-tools`.
- **HTTPS launch profile**: `dotnet run` honoured `launchSettings.json` (https + dev cert)
  over `ASPNETCORE_URLS`; fixed with `--no-launch-profile`.
- **Aspire Seq endpoint** threw at startup without a connection string; added a dummy one.
- **Pipe-hang bug (the subtle one)**: the runner backgrounded the long-lived app *inside* a
  stage that pipes to `tee`, so the stage's pipe never closed and the whole pipeline hung
  after "app serving" — no healthcheck, no tests. Fixed by launching the app detached
  (`setsid </dev/null`) and making the stage only wait for readiness. Exactly the kind of
  non-interactive-execution footgun the sandbox exists to absorb.
- **Git Bash path mangling**: an early Windows `sandbox.ps1` masked a portability question.
  Resolved by making `sandbox.sh` the single canonical dispatcher (Linux target) and running
  it via WSL2 on Windows; Git Bash is unsupported (it rewrites Unix paths into Windows form
  before they reach `docker`). Verified green on real Linux (WSL Ubuntu).

**Takeaway for the role**: the agent was strong at breadth and boilerplate, but the
*headless* failure modes — interactive prompts, launch profiles, telemetry endpoints, pipe
semantics — are precisely where intervention was needed. Streaming everything to stdout +
the `results.json` verdict made every one of these debuggable from `results/<run-id>/`.

## Proof it works
Real artifacts from successful runs (both projects `overall: passed`) are in
**[docs/evidence/](docs/evidence/)** — `results.json`, native test reports (eShop 59 tests,
Medplum jest 4), the live `/healthcheck` body, and failure-path examples (synthesized
`"crashed"` envelope + `skipped` stages). Reproduce: `./sandbox.sh run eshop` / `run medplum`.

## Repository layout
```
sandbox.sh                   dispatcher (up | run | exec | shell | reset | down | setup) — Linux/macOS/WSL
docker/
  compose.eshop.yml          SQL Server + .NET app/build container
  compose.medplum.yml        Postgres + Redis + Node server
  eshop/   Dockerfile, run-checks.sh
  medplum/ Dockerfile, run-checks.sh, medplum.sandbox.config.json
scripts/
  setup.sh                   clone pinned upstream sources
  pins.env                   upstream repo + commit pins
  lib/results.sh             three-channel structured output helpers
results/<run-id>/            results.json + per-stage logs + native reports
docs/recon-notes.md          upstream Docker config analysis + gaps
.upstream/                   pinned checkouts (gitignored)
```
