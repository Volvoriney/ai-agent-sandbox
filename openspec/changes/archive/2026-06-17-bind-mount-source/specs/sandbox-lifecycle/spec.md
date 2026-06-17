# sandbox-lifecycle

## MODIFIED Requirements

### Requirement: Persistent workspace spin-up per project
The sandbox SHALL provide a single non-interactive command that brings up a project's
persistent, exec-able workspace plus its backing services from a clean host. The workspace
container SHALL idle (stay alive), and its source SHALL come from a **bind-mounted host working
copy** (a real git checkout) rather than baked/seeded image content, so an agent's edits land
directly in the host repo.

#### Scenario: Spin up eShopOnWeb workspace
- **WHEN** an operator or pipeline runs `sandbox up eshop`
- **THEN** SQL Server starts and becomes healthy, and the eShopOnWeb workspace container starts
  idle with the host clone bind-mounted read-write at its build path (`/work`)

#### Scenario: Spin up Medplum workspace
- **WHEN** an operator or pipeline runs `sandbox up medplum`
- **THEN** PostgreSQL and Redis become healthy, and the Medplum workspace starts idle with the
  host clone bind-mounted read-write at `/usr/src/medplum`, while the image's pre-installed
  `node_modules` is preserved under the mount via an anonymous volume

### Requirement: Clean state reset without full rebuild
The sandbox SHALL reset the engine state it owns — database data and pre-installed dependencies
— to a pristine state without rebuilding base images. **Source cleanliness is owned by the
harness** (a fresh per-task git checkout / `git clean` on the bind-mounted working copy), not by
the sandbox.

#### Scenario: Reset between agent tasks
- **WHEN** `sandbox reset <project>` is invoked
- **THEN** the DB volume and the dependency anonymous volume are dropped and re-created from the
  cached image (clean DB + restored deps), completing in seconds-to-low-minutes with no image
  rebuild; the harness separately restores source via git

### Requirement: Validation run produces a verdict and leaves the workspace up
The sandbox SHALL run the project's full validation pipeline against the **bind-mounted working
copy's current contents** (the agent's in-progress edits), emit a structured verdict, and leave
the workspace running so the agent can investigate before teardown.

#### Scenario: Validate in-progress edits
- **WHEN** an agent has edited code in the bind-mounted workspace and `sandbox run <project>` is
  invoked
- **THEN** the pipeline builds and tests the edited code as-is, writes `results.json`, and the
  workspace remains up; the edits remain visible in the host working copy for the harness to
  commit
