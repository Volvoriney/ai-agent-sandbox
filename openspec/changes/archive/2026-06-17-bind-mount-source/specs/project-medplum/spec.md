# project-medplum

## MODIFIED Requirements

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
