# project-eshoponweb

## ADDED Requirements

### Requirement: eShopOnWeb builds inside the sandbox
The sandbox SHALL build eShopOnWeb (ASP.NET Core solution) from source non-interactively using the dotnet CLI.

#### Scenario: Clean build
- **WHEN** the build stage runs against a fresh clone pinned to the configured commit/tag
- **THEN** `dotnet build` completes with exit code 0 and no interactive prompts

### Requirement: Database migrations and seed data
The sandbox SHALL run eShopOnWeb's EF Core migrations against a sandboxed SQL Server instance and load seed data, with the SQL Server EULA accepted via environment variable.

#### Scenario: Migrate and seed on fresh database
- **WHEN** the migrate stage runs against a freshly created SQL Server volume
- **THEN** all EF Core migrations apply, seed data loads, and the stage exits 0

### Requirement: Web application responds over HTTP
The sandbox SHALL start the eShopOnWeb web application and verify it answers HTTP requests.

#### Scenario: HTTP health verification
- **WHEN** the app container reports started and the health-check stage issues an HTTP GET to the app's root or health endpoint
- **THEN** the app returns a successful (2xx/3xx) response within the configured timeout

### Requirement: Test suite passes
The sandbox SHALL execute the existing eShopOnWeb test suite headlessly and capture machine-readable results.

#### Scenario: Run unit and integration tests
- **WHEN** the test stage runs `dotnet test` with a TRX/structured logger
- **THEN** the suite completes, results are written to the results directory, and the stage exit code reflects pass/fail
