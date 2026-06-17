# sandbox-lifecycle

## ADDED Requirements

### Requirement: Persistent workspace spin-up per project
The sandbox SHALL provide a single non-interactive command that brings up a project's
persistent, exec-able workspace plus its backing services from a clean host. The workspace
container SHALL idle (stay alive) so a harness can run commands inside it repeatedly.

#### Scenario: Spin up eShopOnWeb workspace
- **WHEN** an operator or pipeline runs `sandbox up eshop` on a host with only Docker installed
- **THEN** SQL Server starts and becomes healthy, and the eShopOnWeb workspace container starts
  idle (no interactive prompt), with its source seeded into a writable `/work`

#### Scenario: Spin up Medplum workspace
- **WHEN** an operator or pipeline runs `sandbox up medplum`
- **THEN** PostgreSQL and Redis start and become healthy, and the Medplum workspace container
  starts idle, ready to be exec'd into

### Requirement: Agent works inside the live workspace
The sandbox SHALL let a harness execute arbitrary commands inside the live workspace
(iterative build/test/inspection) and open an interactive shell, without recreating the
container per command.

#### Scenario: Run a command in the workspace
- **WHEN** `sandbox exec <project> <command>` is invoked while the workspace is up
- **THEN** the command runs inside the workspace container and its stdout/stderr are returned
  to the caller

#### Scenario: Interactive shell
- **WHEN** `sandbox shell <project>` is invoked
- **THEN** an interactive bash session is opened in the live workspace

### Requirement: Validation run produces a verdict and leaves the workspace up
The sandbox SHALL provide a single command that runs the project's full validation pipeline
(build → migrate → run → health-check → test) against the workspace's current contents and
emits a structured verdict. It MUST validate the agent's in-progress edits, not a fresh clone,
and MUST leave the workspace running so the agent can investigate before teardown.

#### Scenario: Validate in-progress edits
- **WHEN** an agent has edited code in the workspace and `sandbox run <project>` is invoked
- **THEN** the pipeline builds and tests the edited code (edits are preserved, not overwritten),
  writes `results.json`, and the workspace remains up afterward

### Requirement: Clean state reset without full rebuild
The sandbox SHALL restore a project to a pristine state (fresh workspace with freshly seeded
source, fresh database state, no leftover agent edits/artifacts) without rebuilding base images.

#### Scenario: Reset between agent tasks
- **WHEN** an agent task has modified workspace source and mutated database state, and
  `sandbox reset <project>` is invoked
- **THEN** the next task starts from base-image state with re-seeded source and an
  empty/re-seeded database, completing in seconds-to-low-minutes (no image rebuild)

### Requirement: Clean teardown
The sandbox SHALL tear down a project completely, removing its containers, networks, and
run-scoped volumes.

#### Scenario: Teardown after a task
- **WHEN** `sandbox down <project>` is invoked
- **THEN** no containers, networks, or anonymous volumes belonging to that project remain

### Requirement: Independent project lifecycles
Each project's environment SHALL be operable independently: starting, resetting, or tearing
down one project MUST NOT affect the other.

#### Scenario: Concurrent isolated environments
- **WHEN** both project environments are up and `sandbox reset eshop` is invoked
- **THEN** the Medplum environment continues running unaffected
