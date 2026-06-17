# project-medplum Specification

## Purpose
TBD - created by archiving change build-agent-sandbox. Update Purpose after archive.
## Requirements
### Requirement: Medplum server builds inside the sandbox
The sandbox SHALL build the Medplum server from the **bind-mounted host working copy** (mounted
read-write at `/usr/src/medplum`) non-interactively (npm/Turborepo). The image's pre-installed
`node_modules` SHALL be preserved under the mount via an anonymous volume, so the build runs
incrementally without re-running `npm ci`. The workspace SHALL be a real git repository (the
host clone), so an agent's edits are committable.

#### Scenario: Clean build from the mounted working copy
- **WHEN** the build stage runs against the bind-mounted source with the dependency anonymous
  volume present
- **THEN** `turbo run build --filter=@medplum/server` compiles using the preserved
  `node_modules` and writes `dist`, completing with exit code 0 and no interactive prompts

#### Scenario: Workspace is a git repository
- **WHEN** an agent edits files in the bind-mounted workspace
- **THEN** `git diff` reflects the changes against the host clone's history (no patch-export
  step required), ready for the harness to commit and open a PR from the host

### Requirement: Database migrations run
The sandbox SHALL run Medplum's database migrations against sandboxed PostgreSQL (with Redis available) on startup.

#### Scenario: Migrate on fresh database
- **WHEN** the server starts against freshly created PostgreSQL and Redis volumes
- **THEN** migrations apply automatically and the server reaches ready state with exit-code-0 stage result

### Requirement: API responds to health checks
The sandbox SHALL verify the Medplum API answers its health-check endpoint.

#### Scenario: Health check verification
- **WHEN** the health-check stage issues an HTTP GET to the server's `/healthcheck` endpoint
- **THEN** the API returns a successful response within the configured timeout

### Requirement: Test suite passes
The sandbox SHALL execute the Medplum test suite (at minimum the server package's tests if the full monorepo suite exceeds the time budget) headlessly with a JSON reporter.

#### Scenario: Run tests with structured output
- **WHEN** the test stage runs the configured test command
- **THEN** the suite completes, JSON results are written to the results directory, and the stage exit code reflects pass/fail
- **AND** any scope reduction (subset of packages) is recorded in the run summary

