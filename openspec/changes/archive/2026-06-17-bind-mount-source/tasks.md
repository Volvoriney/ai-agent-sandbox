# Tasks: bind-mount-source

## 1. eShop → bind-mount

- [x] 1.1 `compose.eshop.yml`: mount `../.upstream/eshop:/work` (rw); remove the `/src:ro` mount and the seed-once `command`
- [x] 1.2 `eshop/run-checks.sh`: drop the `prepare` seed stage (source already present at `/work`); build/test `/work` as-is
- [x] 1.3 `eshop/Dockerfile`: drop the seed-once comment/CMD note (source no longer seeded)

## 2. Medplum → bind-mount + preserve baked deps

- [x] 2.1 `compose.medplum.yml`: mount `../.upstream/medplum:/usr/src/medplum` (rw) + anonymous volume `/usr/src/medplum/node_modules`
- [x] 2.2 Verify `turbo build @medplum/server` works against the mounted source with preserved `node_modules` (watch for non-hoisted nested deps)

## 3. Dispatcher + clean-state

- [x] 3.1 `sandbox.sh`: confirm `reset`/`down -v` drops the `node_modules` anonymous volume and DB; document that source clean-state is harness-owned (git)

## 4. Verify

- [x] 4.1 eShop: `up` → edit `/work` → `run` (passed) → confirm edit visible on host repo + `git diff` shows it → `reset` → DB/deps clean
- [x] 4.2 Medplum: `up` → `run` (build+migrate+healthcheck+test passed) on mounted source → `git diff` works in workspace
- [x] 4.3 N/A — Medplum bind-mount + anon node_modules passed (hoisted deps sufficient); no fallback needed

## 5. Docs

- [x] 5.1 README + proof-of-work: bind-mount model, harness-owned source clean-state, PR-from-host flow, Windows-WSL bind perf note
