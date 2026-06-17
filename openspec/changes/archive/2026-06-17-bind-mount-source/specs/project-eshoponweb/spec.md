# project-eshoponweb

## MODIFIED Requirements

### Requirement: eShopOnWeb builds inside the sandbox
The sandbox SHALL build eShopOnWeb from the **bind-mounted host working copy** (mounted
read-write at `/work`) non-interactively using the dotnet CLI, restoring against the NuGet
packages pre-installed in the image cache (`/nuget`, outside the source tree, so the mount does
not shadow them).

#### Scenario: Clean build from the mounted working copy
- **WHEN** the build stage runs against the bind-mounted source
- **THEN** `dotnet build` restores offline from the baked NuGet cache and compiles, completing
  with exit code 0 and no interactive prompts, with build output written into the mounted `/work`
