# output-capture Specification

## Purpose
TBD - created by archiving change build-agent-sandbox. Update Purpose after archive.
## Requirements
### Requirement: Structured run summary
Every validation run SHALL produce a machine-readable `results.json` summarizing each stage
(prepare/build/migrate/start/health-check/test, as applicable) with status, duration, and exit
code, plus an overall pass/fail.

#### Scenario: Successful run summary
- **WHEN** a full run of either project completes
- **THEN** `results/<run-id>/results.json` exists on the host with one entry per stage, each
  containing status, duration, and exit code, and an overall result field

#### Scenario: Failed stage is recorded, later stages skipped
- **WHEN** a stage fails (e.g., build error in agent-generated code)
- **THEN** the summary marks that stage failed with its exit code, marks subsequent stages
  skipped, and the run's overall exit code is non-zero

#### Scenario: Runner death is reported, not silent
- **WHEN** the runner produces no `results.json` (container crash/OOM)
- **THEN** the dispatcher synthesizes an envelope with `overall: "crashed"`, the exit code, a
  reason, and a pointer to the log, so the consumer never gets silence

### Requirement: Logs stream to stdout; agent reads background logs from files
Logs SHALL be written to stdout/stderr (not container-managed logfiles), captured by the
caller/log driver. Because code inside the sandbox cannot use `docker logs` (no host socket),
long-running background processes (the app/server) SHALL also tee their output to
agent-readable files under the results directory.

#### Scenario: Operator/aggregator capture
- **WHEN** a run executes
- **THEN** the combined stdout stream is captured to `results/<run-id>/run.log` (the local
  stand-in for a log aggregator)

#### Scenario: Agent reads background-process logs from inside
- **WHEN** the app/server is running and an agent (inside the sandbox) needs its logs
- **THEN** it reads `results/latest/app.log` (eShop) or `results/latest/server.log` (Medplum)
  via `exec`, without requiring `docker logs` or the Docker socket

### Requirement: Tool-native machine-readable test reports preserved
The sandbox SHALL capture native structured test reports (TRX for dotnet, JSON reporter output
for the Node toolchain) as artifacts in the results directory.

#### Scenario: Test artifacts collected
- **WHEN** the test stage completes (pass or fail)
- **THEN** the structured test report is present under `results/<run-id>/`

### Requirement: Results accessible from the host without entering containers
Run results SHALL be written to a host-accessible location (bind mount) so a pipeline can
collect them after teardown. A stable `results/latest` pointer SHALL reference the newest run.

#### Scenario: Collect after teardown
- **WHEN** the run finishes and the composition is torn down
- **THEN** `results/<run-id>/` (and `results/latest`) remain intact on the host

