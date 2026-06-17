# isolation-and-resources Specification

## Purpose
TBD - created by archiving change build-agent-sandbox. Update Purpose after archive.
## Requirements
### Requirement: Resource limits on all containers
Every container in a sandbox composition SHALL declare memory and CPU limits (SQL Server ≥ 2 GB to satisfy its floor; build containers sized for their toolchain).

#### Scenario: Limits enforced
- **WHEN** a composition is up
- **THEN** `docker inspect` shows non-zero memory and CPU limits on every container in the composition

### Requirement: Network isolation
Sandbox containers SHALL communicate only over composition-internal networks; only the application HTTP port MAY be published, and only on localhost. Containers MUST NOT have access to the Docker socket or host filesystem beyond explicitly defined mounts (source input, results output).

#### Scenario: No cross-composition access
- **WHEN** both project compositions are running
- **THEN** a container in the eShopOnWeb composition cannot reach Medplum's PostgreSQL, and vice versa

#### Scenario: No host control plane access
- **WHEN** arbitrary code executes inside an app container
- **THEN** it cannot reach the Docker socket and cannot write outside its container filesystem and the designated results mount

### Requirement: Non-root execution where supported
Application and build containers SHALL run as a non-root user wherever the upstream base images support it; exceptions MUST be documented in the README.

#### Scenario: Non-root app container
- **WHEN** the app container is running
- **THEN** the main process UID is non-zero, or the README documents why root is required for that container

### Requirement: Documented isolation limits
The README SHALL state explicitly that container isolation is not a VM-grade boundary and name the next escalation step (e.g., microVM runtimes) for hostile-code scenarios.

#### Scenario: Security section present
- **WHEN** a reviewer reads the README
- **THEN** it contains a security/isolation section covering boundaries, what sandboxed code can access, and known limitations

