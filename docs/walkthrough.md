# Walkthrough outline (15–20 min)

A suggested flow for the live demo / presentation. Optimize for clarity of thinking.

## 1. Framing (2 min)
- What this is: the **execution environment an AI harness runs inside**, not the harness.
- Consumer is a pipeline, not a human → non-interactive, disposable, instrumented, isolated.
- The two projects were chosen to force a *generalizable* design (conflicting DB/runtime/build).

## 2. The demo (5 min) — lead with working software
```bash
./sandbox.sh run eshop       # build → migrate+seed → HTTP 200 → tests → results.json
./sandbox.sh run medplum     # build → migrate → /healthcheck → tests → results.json
```
Then show the **agent loop** — the workspace stays alive, agent works *inside*:
```bash
./sandbox.sh up eshop                          # persistent workspace
./sandbox.sh exec eshop dotnet test tests/...  # iterate: build/test (incremental)
./sandbox.sh exec eshop tail -f /results/latest/app.log   # read background app logs
./sandbox.sh shell eshop                       # poke around, then…
./sandbox.sh down eshop
```
(On Windows: run from a WSL2 shell — single bash dispatcher, Linux is the target.)
- Open `results/<run-id>/results.json` for each — per-stage status/duration/exit, `overall`.
- Show the Medplum `/healthcheck` body (`postgres:true, redis:true`).

## 3. The decisions that matter (6 min)
- **Two isolated compositions** (D1) + thin dispatcher → show the cross-composition network
  test (eShop can't reach Medplum's Postgres by name or IP).
- **Five-stage contract + same results schema** → generality lives in the structure; a third
  repo = one compose file + one runner. Built for two, shaped for N.
- **Startup strategy** (D3): slow once (base image), seconds per run; lockfile-keyed restore;
  tiered DB (idempotent migrations — show the 4s vs 97s start times).
- **Output capture** (D4): one-shot container → logs to **stdout** (12-factor, captured by the
  log driver; locally tee'd to `run.log`), **`results.json`** as the verdict artifact,
  exit-code synthesis → show the `"crashed"` envelope on a killed run.

## 4. The AI-usage story (4 min) — the part the brief asks for
- Agent nailed recon + architecture + boilerplate.
- Where it needed intervention: the **headless footguns** — SDK drift, wasm workload, central
  MSBuild props, HTTPS launch profile, Aspire Seq endpoint, and the **pipe-hang bug** (long-
  lived process holding a stage's `tee` pipe). These ARE the role: the sandbox exists to
  absorb exactly these non-interactive failure modes, and the three-channel capture made each
  one debuggable from `results/`.

## 5. Honest limits / next steps (2 min)
- Container ≠ VM boundary → microVM (gVisor/Kata/Firecracker) for hostile code.
- .NET build container runs as root (bind-mount writes) → run as image `app` user next.
- Medplum tests scoped to the server healthcheck suite for time → widen with budget.
- Tiered DB snapshot (tier 2) not yet implemented — tier 1 (migrate-per-run) is correct today.
