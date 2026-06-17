# sandbox-lifecycle

## ADDED Requirements

### Requirement: Deterministic host-path resolution
The sandbox SHALL resolve all host paths used by a composition (build context, Dockerfile, and
bind-mount sources) unambiguously from the repository root via a single `SANDBOX_ROOT` anchor,
independent of the caller's working directory. The dispatcher SHALL set `SANDBOX_ROOT` before
invoking Compose.

#### Scenario: Paths resolve the same regardless of CWD
- **WHEN** the dispatcher runs a lifecycle verb for a project
- **THEN** every host path in the composition resolves under `SANDBOX_ROOT` (the repo root), so
  the source mount, results mount, build context, and Dockerfile point at the same locations no
  matter which directory the command was launched from
