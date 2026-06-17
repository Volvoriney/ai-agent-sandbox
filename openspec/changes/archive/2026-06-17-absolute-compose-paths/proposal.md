# Proposal: absolute-compose-paths

## Why

The compose files use a mix of relative host paths (`../.upstream/eshop`, `./eshop/run-checks.sh`,
`../scripts/lib/results.sh`, `../results`). They work — Compose resolves them relative to the
compose file's directory — but the mixed `./` + `../` jumping is hard to read, easy to break if
files move, and `build.context` vs `volume` paths can resolve from different bases across Compose
versions. A reader can't tell at a glance where a path lands.

## What Changes

- Compose files reference every host path via an explicit **`${SANDBOX_ROOT}`** prefix
  (`${SANDBOX_ROOT}/.upstream/eshop`, `${SANDBOX_ROOT}/docker/...`, `${SANDBOX_ROOT}/results`),
  including `build.context` and `dockerfile`.
- The dispatcher (`sandbox.sh`) **exports `SANDBOX_ROOT="$ROOT"`** before every compose call, so
  the var is always set when invoked normally.
- Behavior is identical — this is a readability/maintainability refactor, no requirement change.

## Capabilities

### Modified Capabilities
(None — no requirement/behavior change; internal path-style refactor.)

### New Capabilities
(None.)

## Impact

- Changed: `docker/compose.eshop.yml`, `docker/compose.medplum.yml`, `sandbox.sh`.
- Direct `docker compose -f …` invocation now needs `SANDBOX_ROOT` exported (the dispatcher sets
  it); documented in the compose-file header + README.
- No spec deltas.
