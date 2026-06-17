# Design: absolute-compose-paths

## Context

Pure readability/maintainability refactor of host-path references in the compose files. No
behavior change, no requirement change — so no spec deltas.

## Decisions

### D1: Absolute host paths via `${SANDBOX_ROOT}`
Every host path in the compose files is written `${SANDBOX_ROOT}/<path-from-repo-root>` —
`build.context`, `dockerfile`, and all bind-mount sources. The dispatcher exports
`SANDBOX_ROOT="$ROOT"` (the repo root it already computes) before each `docker compose` call.
- *Why:* explicit and unambiguous — a reader sees exactly where each path lands, no `./`/`../`
  base-directory guessing, and no divergence between how `build.context` and `volumes` resolve.
- *Trade:* a direct `docker compose -f …` (bypassing the dispatcher) must export `SANDBOX_ROOT`
  first. Acceptable: the dispatcher is the entry point; documented in the compose header.
- *Rejected alt:* `--project-directory "$ROOT"` + `./` paths — removes `../` but still relies on
  base-directory resolution that differs subtly across Compose versions for build vs volumes.

## Risks / Trade-offs
- [Direct compose use without the env var → empty paths] → documented; dispatcher always sets it.
- [WSL paths are `/mnt/c/...`] → absolute already; Docker Desktop handles the bind mounts.

## Open Questions
(None.)
