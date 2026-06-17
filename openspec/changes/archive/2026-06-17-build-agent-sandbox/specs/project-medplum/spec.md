# project-medplum

## ADDED Requirements

### Requirement: Medplum server builds inside the sandbox
The sandbox SHALL build the Medplum server from its TypeScript monorepo non-interactively (npm/Turborepo), with dependencies pre-restored in a cached image layer keyed on lockfiles.

#### Scenario: Clean build
- **WHEN** the build stage runs against a fresh clone pinned to the configured commit/tag
- **THEN** `npm ci` and the server build complete with exit code 0 and no interactive prompts

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
