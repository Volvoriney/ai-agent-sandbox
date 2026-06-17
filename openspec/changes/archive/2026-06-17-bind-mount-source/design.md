# Design: bind-mount-source

## Context

The sandbox is the environment an AI harness runs inside; the agent edits code, the sandbox
validates it, and the **harness** turns the result into a PR. Getting edits out as a PR is far
simpler if they live in a real git working copy the host can see — which is what bind-mounting
the host clone achieves. This change moves source delivery from baked/seeded to bind-mounted,
and shifts source clean-state ownership to the harness.

## Goals / Non-Goals

**Goals:**
- Agent edits land directly in a host working copy that has `.git` (both projects).
- Container is a pure executor; harness commits/pushes/PRs from the host (no creds in the box).
- Keep deps pre-installed (fast incremental builds) despite mounting source.
- Preserve clean-state guarantees: sandbox resets DB + deps; harness resets source via git.

**Non-Goals:**
- Building the harness or the PR-push logic (out of scope; we expose the mounted repo).
- Run-time egress lockdown (documented future work).
- Solving every npm-workspace nested-node_modules edge; verify + document fallback.

## Decisions

### D1: Bind-mount the host clone read-write
Each composition mounts the pinned host checkout (`.upstream/<project>`) into the workspace
read-write at the build path. The agent edits there; edits are visible on the host immediately.
- *Why:* host clone has `.git` → harness does `git diff/commit/push` from the host. No
  `.git`-baking, no patch-export. Container needs no Docker socket and no GitHub creds.
- eShop → mount at `/work` (the path the runner already builds in). Drop the read-only `/src`
  mount, the rsync seed, the seed-once container command, and the `prepare`-seed runner stage.
- Medplum → mount at `/usr/src/medplum`.

### D2: Preserve baked deps under the mount (Medplum)
Mounting host source over `/usr/src/medplum` shadows the image's baked `node_modules`. Use a
Docker **anonymous volume at `/usr/src/medplum/node_modules`** so the image's deps survive the
mount (classic node-in-docker pattern). `turbo build` regenerates `dist` on the mounted source.
- *Why:* keeps `npm ci` out of the hot path; npm workspaces hoist deps to the root
  `node_modules`, which the anonymous volume covers.
- *Risk:* non-hoisted nested `packages/*/node_modules` would be shadowed (host has none). If
  build/test fail for that reason, fall back to baked source + `git init` baseline + patch
  export, documented.
- eShop needs no equivalent: NuGet lives in a separate cache (`/nuget`), outside the source
  tree, so mounting source doesn't shadow it.

### D3: Clean-state ownership splits
- **Source** cleanliness → **harness**: it mounts a fresh per-task checkout (or runs
  `git clean -fdx`/`git reset --hard` on the mount) between tasks. The sandbox does not reseed
  source anymore.
- **DB + deps** → **sandbox**: `reset` = `down -v && up`. `down -v` drops the `node_modules`
  anonymous volume (and DB data); `up` re-creates the anonymous volume from the image (deps
  restored) and a clean DB.
- *Why:* the repo is the harness's artifact (it makes the PR); the engine state is the
  sandbox's. Each owns what it's responsible for.

### D4: PR flow stays outside the sandbox
Agent commits locally in the mounted repo; the harness pushes + opens the PR from the host
(creds + network there). Reinforced by the future run-time egress lockdown: with egress closed
during runs, push-from-sandbox is impossible by design — export-and-push-outside is the model.

## Risks / Trade-offs

- [Medplum nested node_modules shadowed by mount] → verify build+test; fall back to baked +
  `git init` + patch export if broken.
- [Windows-via-WSL bind perf over /mnt/c for the large Medplum tree] → slow on Windows dev;
  production is Linux (native bind, fast). Documented.
- [rw host mount widens the container's host-fs write surface vs ro+copy] → acceptable: the
  mount is the harness's throwaway per-task checkout, and that's exactly where edits should go.
- [Pinned `.upstream` clone is shared, not per-task] → for the demo it is mutated in place;
  document that a real harness mounts a per-task checkout and owns `git clean`.

## Open Questions
- Should `reset` also `git clean` the mounted source as a convenience, or leave all source
  hygiene to the harness? (Lean: leave to harness; `reset` stays DB/deps-scoped.)
