# Proposal: bind-mount-source

## Why

Today the sandbox delivers source code to the workspace by **baking or seeding** it:
- eShop copies a read-only `/src` into a writable `/work` (rsync seed-once).
- Medplum bakes the full source into the image at `/usr/src/medplum`.

Both keep the agent's edits *inside the container*, which forces extra plumbing to get those
edits back out as a pull request: Medplum's image has **no `.git`** (its `.dockerignore` drops
it), so an agent can't `git diff`/`commit` there, and producing a PR would need a patch-export
step. It also means the sandbox owns source clean-state via reseed/rebuild.

Bind-mounting the **host working copy** (which already has `.git`) into the container instead
makes the agent's edits land **directly in the repo**. The container stays a pure executor; the
**harness commits/pushes/opens the PR from the host** (creds + network stay outside the
untrusted box). This removes the Medplum `.git` gap and the patch-export need, shrinks images to
deps-only, and matches the brief's "validate before it becomes a PR" — sandbox validates,
control plane PRs.

## What Changes

- **eShop**: mount the host clone read-write at `/work`; drop the read-only `/src` mount, the
  `rsync` seed, the seed-once container command, and the `prepare`-seed runner stage. Build
  directly in the mounted `/work`.
- **Medplum**: mount the host clone read-write at `/usr/src/medplum` with an **anonymous volume
  preserving the image's baked `node_modules`** (so deps aren't shadowed by the mount); `turbo`
  rebuilds `dist` on the mounted source.
- **Clean-state ownership splits**: the **harness** owns *source* cleanliness (fresh per-task
  `git` checkout / `git clean`); the **sandbox** still owns DB + deps reset (`reset` =
  `down -v && up`, which also drops the `node_modules` anonymous volume → re-populated from the
  image).
- **PR flow**: agent edits land on the host repo → harness commits/pushes/PRs from the host. No
  `.git`-baking, no patch-export.

## Capabilities

### Modified Capabilities
- `sandbox-lifecycle`: source comes from a bind-mounted host repo; `run` validates the mounted
  working copy as-is; source clean-state is harness-owned, sandbox owns DB/deps reset.
- `project-eshoponweb`: build/migrate/run/test operate on the bind-mounted `/work`.
- `project-medplum`: build/run/test operate on the bind-mounted source with baked `node_modules`
  preserved via anonymous volume; workspace is a real git repo (host clone).

### New Capabilities
(None.)

## Impact

- Changed: `docker/compose.eshop.yml`, `docker/compose.medplum.yml`, `docker/eshop/run-checks.sh`
  (drop prepare-seed), `docker/eshop/Dockerfile` (drop seed-once command note), `sandbox.sh`
  (reset also drops anonymous volumes), README/proof docs.
- No new external dependencies. Images shrink (eShop no longer needs source-copy tooling on the
  hot path; Medplum image still bakes deps but source is mounted).
- Risk: Medplum npm-workspace **nested** `node_modules` (non-hoisted) could be shadowed by the
  mount; verify build+test still pass, fall back to baked-source + `git init` if not.
- Windows-via-WSL bind-mount perf over `/mnt/c` is slower for large trees (Medplum); production
  is Linux, so non-issue there — documented.
