# Proof of work — evidence bundle

Real artifacts captured from successful runs on the final (bind-mount) architecture, Linux
(WSL2 Ubuntu, Docker 29.5.3). Reproduce with `./sandbox.sh run eshop` / `run medplum`.

## eShopOnWeb — `overall: passed`
- [`eshop/results.json`](eshop/results.json) — per-stage verdict (prepare-free; build → start → healthcheck → test).
- [`eshop/run.trimmed.txt`](eshop/run.trimmed.txt) — stage markers + results.
- Native test reports (verbatim): [`UnitTests.trx`](eshop/UnitTests.trx), [`FunctionalTests.trx`](eshop/FunctionalTests.trx), [`IntegrationTests.trx`](eshop/IntegrationTests.trx).
- **Tests: 59 passed** (Unit 44 · Functional 12 · Integration 3), 0 failed.
- Health check: `HTTP 200` on `/` (app served real HTML; EF migrations + seed ran on startup).

## Medplum — `overall: passed`
- [`medplum/results.json`](medplum/results.json) — build → start (auto-migrate) → healthcheck → migrate-testdb → test.
- [`medplum/run.trimmed.txt`](medplum/run.trimmed.txt) — stage markers + results.
- [`medplum/jest-server.json`](medplum/jest-server.json) — native jest report. **Tests: 4 passed, 4 total.**
- [`medplum/healthcheck.json`](medplum/healthcheck.json) — live `/healthcheck` body:
  `{"ok":true,"version":"5.1.9-...","postgres":true,"redis":true,...}` (DB + Redis connected).
- Test scope recorded in `results.json`: server package, healthcheck suite (full monorepo suite cut for time budget — per spec).

## Failure-path (the output-capture guarantee)
- [`failure-path/eshop-crashed.results.json`](failure-path/eshop-crashed.results.json) — a runner killed mid-stage produced no `results.json`, so the dispatcher **synthesized** `{"overall":"crashed","exitCode":143,...}` — never silent.
- [`failure-path/medplum-failed-start.results.json`](failure-path/medplum-failed-start.results.json) — a failed `start` stage marks later stages `skipped` and `overall: failed`.

## Not included here (human-facing, for the presentation)
- Browser screenshots (eShop store UI at `:8080`; Medplum `/healthcheck` + `/fhir/R4/metadata`) — bring both up with `scripts/serve-demo.sh`.
- A terminal recording of `sandbox.sh run <project>` going green.
