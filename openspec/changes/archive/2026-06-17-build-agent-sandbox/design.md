# Design: build-agent-sandbox

## Context

This is a take-home interview task (~2 hours implementation budget) for a DevOps Engineer role. The sandbox is the execution environment an AI harness runs inside — not the harness itself. It must support non-interactive execution, deterministic builds, clean state between runs, and structured output capture, "hundreds of times a day."

Two target projects with deliberately conflicting requirements:

| | eShopOnWeb | Medplum |
|---|---|---|
| Runtime | .NET (ASP.NET Core) | Node.js (TypeScript) |
| Database | SQL Server | PostgreSQL + Redis |
| Build system | dotnet CLI | npm / Turborepo |
| "Works" means | builds, migrations run, seed data loads, web app answers HTTP, tests pass | server builds and starts, migrations run, API health checks pass, tests pass |

Both upstream repos ship some Docker configuration already — start from those, identify gaps.

## Goals / Non-Goals

**Goals:**
- One command per project to go from clean checkout to "proven working" (build + migrate + run + health check + tests).
- Clean state between agent runs without paying full image rebuild cost each time.
- Everything headless: no prompts, no license wizards, no interactive credential entry (SQL Server EULA via env var `ACCEPT_EULA=Y`, non-interactive npm/dotnet flags).
- Structured results (JSON summary: per-stage status, durations, test counts, exit codes) written to a well-known location the pipeline can collect.
- Sensible resource caps and isolation boundaries for running untrusted generated code.

**Non-Goals:**
- Building the AI harness/orchestrator itself.
- Production-grade hardening (gVisor/Kata, seccomp profiles) — documented as future work.
- Handling every edge case; depth on the chosen design considerations beats breadth.
- Visual polish.

## Decisions

### D1: Two isolated compositions, not one shared sandbox
Each project gets its own docker-compose project (`compose.eshop.yml`, `compose.medplum.yml`) with isolated networks and volumes.
- *Why:* The stacks share nothing (different DB engines, runtimes, build tools). An agent harness prefers isolation: a failed/poisoned eShop run can never corrupt a Medplum run; compositions can be spun up/torn down independently and in parallel.
- *Alternative considered:* one mega-compose with both DB engines always running — wastes ~3 GB RAM when an agent only needs one project, and couples the lifecycles.
- A thin top-level CLI (`sandbox.ps1` / `sandbox.sh up|run|reset|down <project>`) unifies the interface so the consumer doesn't care that internals differ.

### D2: Run each project's native database — no consolidation
SQL Server for eShopOnWeb, PostgreSQL + Redis for Medplum.
- *Why:* eShopOnWeb's EF Core migrations target SQL Server; Medplum is deeply Postgres-specific. Porting either is out of budget and defeats "test against reality."
- Schema isolation comes free from composition isolation (D1); within a composition, ephemeral DB volumes give per-run isolation.

### D3: Clean state + startup performance — slow is allowed exactly once
There are **three distinct "times," and only the first is allowed to be slow:**

| Phase | Frequency | Budget | Strategy |
|---|---|---|---|
| Cold base-image build | Once (or when deps change) | Minutes — fine | SDK + restored deps baked into a layer |
| Warm spin-up per run | Hundreds/day | Seconds | Fresh container from cached base + ephemeral DB |
| In-run iteration (edit→build→test) | Many times per run | Seconds | Incremental build, cached package dirs |

The agent loop is `edit → build → test → repeat`; that hot path must never re-restore dependencies or rebuild the base image. Mechanisms:

- **Multi-stage Dockerfiles with lockfile-keyed dependency layers.** Copy only the manifests first (`*.csproj`/`*.sln`, `package.json`/`package-lock.json`), restore, *then* copy source. Editing a source file invalidates only the source layer; `dotnet restore` / `npm ci` stays cached.
- **Pre-built per-project base image** (`eshop-base`, `medplum-base`) with deps already restored — a run starts *from* it, skipping dependency fetch. Rebuilt only when lockfiles change (setup script keys on lockfile hash).
- **BuildKit cache mounts** for the package caches (`--mount=type=cache` on `~/.nuget/packages`, `~/.npm`) so even a cache-busted restore doesn't re-download the world.
- **Pre-pull heavy images in setup** (SQL Server ~2 GB) so the slow pull never lands on the hot path; DB comes up once per run with a generous healthcheck `start_period`, and the agent iterates code builds against the already-warm DB.
- **`reset` = recreate, not rebuild.** `docker compose down -v && up` drops the ephemeral DB volume and starts a fresh container from the cached base image — clean state in seconds because the expensive layers are never touched.
- Source code mounted or copied at run time, so agent-modified code never taints the image.

### D3a: Tiered database state — incremental, with cold fallback
The DB is cached like dependencies: a tier is a fallback for the one above it.

```
1. Source of truth  : empty DB + full migration history    (always correct, slowest)
2. Cached snapshot   : pre-migrated + seeded volume,
                       keyed on hash(migrations dir + seed)  (reused while schema unchanged)
3. Per-run ephemeral : throwaway copy of the snapshot        (mutated freely, dropped on reset)
```

- Migrations are **incremental deltas with recorded history** (`__EFMigrationsHistory`; Medplum's tracking) and the migrate stage is **idempotent** — a schema-changing PR applies *only* the pending migration on top of tier 2, not a full replay. Running it *is* the test for that ticket (brief: "migrations run").
- A schema change re-keys the snapshot, so tier 2 is regenerated **once** (same pattern as rebuilding the deps layer when a lockfile changes), then re-cached. Never a rebuild of the base image or a deps re-restore.
- Cold fallback (tier 1: fresh DB + run all migrations every run) is fully correct and simple — **tier 2 is an optimization added only if cold migrate time hurts.** For a 2-hour budget, ship tier 1; document tier 2.
- *Snapshot mechanism:* logical dump/restore for small seed data (`pg_dump`/`psql`, SQL Server `BACKUP`/`RESTORE .bak`) — engine-native and version-tolerant; filesystem volume tarball as the faster-restore alternative for large datasets (requires matching DB version + clean shutdown before snapshot).

### D4: Output capture — logs to stdout (12-factor), structured verdict as an artifact
The brief asks for structured data "**not just** a scrolling terminal log". Two separable
concerns with different destinations:

1. **Raw logs → stdout.** The runner (and the app/server it launches) write everything to
   stdout/stderr. `run` exec's the runner into the persistent workspace, so that stream
   reaches the dispatcher (the exec client), which tees it to `results/<run-id>/run.log` —
   the local stand-in for the harness's log capture / aggregator (Loki/CloudWatch/Splunk) in
   production. The container manages **no logfiles** (12-factor). Capture happens *outside*
   the container, so logs survive even if the container dies mid-run.
2. **Structured verdict → `results.json` artifact.** Per-stage status/exitCode/duration,
   skipped stages on failure, `overall`. This is a CI *artifact* (like JUnit XML or a build
   report), not a log stream, so a file in the bind-mounted results dir is correct. Native
   test reports (TRX, jest JSON) are written alongside it as artifacts.
3. **Exit code + outer synthesis — the guarantee.** `sandbox.sh` returns the runner's exit
   code; if `results.json` is missing (runner died), it **synthesizes** a `"crashed"` envelope
   (exit code + reason + `run.log` pointer) so the consumer never gets silence.

- *Why:* raw logs belong where the platform already captures them (stdout, via the exec
  client / log driver), the verdict belongs in an artifact, and neither depends on the thing
  that just crashed.
- *The deliverable is the schema + the contract, not the JSON syntax.* `results/` is the local
  stand-in for an artifact store; `run.log` for the log aggregator. The seam (work→stdout,
  verdict→artifact, signal via exit code) is identical whether the collector is `sandbox.sh`
  or a Kubernetes Job + Fluent Bit.

### D4b: Persistent workspace + exec (the agent works *inside*)
The brief says the sandbox is "the infrastructure an AI harness runs **inside**" — a place
generated code is built/tested/validated. So the app/build container is a **persistent
workspace** (idles via the image's `sleep infinity`), not a fixed one-shot script:
- `up` brings up the workspace + backing services; the harness `exec`s in to build/edit/test
  and iterate (incremental builds, fast), and `shell`s in to poke around / debug.
- `run` exec's the canonical validation pipeline (`run-checks`) into the same live workspace
  and emits `results.json` — the pre-PR gate. It leaves the workspace **up** so the agent can
  keep investigating before teardown.
- Lifecycle (`up`/`reset`/`down`) is driven by the host/control-plane, **not** by code inside
  the container — so no Docker socket is mounted (keeps the isolation boundary, D5).
- `/work` is **seeded once** from the read-only pristine `/src` (at container start / first
  run, guarded by a `.seeded` marker — never `--delete`d), so `run` validates the agent's
  in-progress edits rather than overwriting them. Clean state between *tasks* comes from
  `reset` (`down -v && up`: fresh container → fresh seed + fresh DB volume, seconds, no
  rebuild). The workspace persists *within* a task; state resets *between* tasks.
- *Revision note:* earlier iterations tried (a) idle + `exec` with per-stage logfiles, then
  (b) a one-shot `compose run` container. (a) filed raw logs against 12-factor; (b) gave no
  live workspace to iterate/poke in (wrong for an agent sandbox). Final model = persistent
  workspace + `exec`/`shell`, logs→stdout, verdict→artifact.

### D5: Resource limits and isolation boundaries
- Compose-level `mem_limit` / `cpus`: SQL Server 2.5 GB, Postgres 1 GB, app/build containers 4 GB (Medplum's Turborepo build is memory-hungry).
- App containers run as non-root where the upstream images allow; no Docker socket mounted; internal compose networks — only the app's HTTP port published, and only to localhost.
- Documented honestly: container isolation is not a VM boundary; for truly hostile code, a microVM runtime would be the next step.

### D6: Implementation-heavy deliverable
Working Docker setup + README over a pure design doc — the brief states a working single-project sandbox beats an elaborate non-booting design for two, so the task order (tasks.md) gets eShopOnWeb fully green first, then Medplum, then polish.

## Risks / Trade-offs

- [SQL Server image is heavy and slow to become healthy] → healthcheck with generous `start_period`; pre-pull images in setup script; document ~2 GB RAM floor.
- [Medplum monorepo build may blow the 2-hour budget] → use upstream's published images/Docker config where possible; if full test suite is too slow, run the server package's tests and document the cut.
- [Upstream repos drift (migrations/build steps change)] → pin to a specific tag/commit in the setup script for reproducibility.
- [Windows host (this machine) vs. Linux containers] → all scripts in both PowerShell and bash; avoid bind-mount perf pitfalls by copying source into containers for build stages.
- [Container ≠ hard security boundary] → stated explicitly in README; mitigations limited to non-root, no socket, network scoping, resource caps.

## Open Questions

- Pin upstream repos to which tag/commit? (Resolve during implementation: latest stable tag at time of build.)
- Run Medplum's full test suite or server-package subset within time budget? (Decide after first timed run.)
