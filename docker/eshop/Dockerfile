# syntax=docker/dockerfile:1
#
# eShopOnWeb sandbox base image: .NET 10 SDK + pre-restored NuGet packages.
#
# Build context is the pinned upstream checkout (.upstream/eshop). We copy ONLY the
# solution + project files before restoring, so the restore layer is keyed on project
# definitions — editing source code never busts it (design D3). Packages are restored
# into /nuget and baked into the image so per-run builds restore offline in seconds.
#
# The Aspire AppHost project (eShopWeb.AppHost) is intentionally skipped: it requires the
# Aspire workload/SDK and is the orchestrator, not part of "build + run the web app".

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS base

ENV NUGET_PACKAGES=/nuget \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    ASPNETCORE_ENVIRONMENT=Docker

WORKDIR /src

# Web references BlazorAdmin (Microsoft.NET.Sdk.BlazorWebAssembly), which needs the
# wasm-tools workload — without it, restore fails with NETSDK1124. Source-independent
# layer, so it stays cached across source edits.
RUN dotnet workload install wasm-tools

# --- dependency layer: project files only, restore baked into the image ---
# Central config FIRST: Directory.Packages.props holds the TargetFramework AND all package
# versions (central package management); global.json pins the SDK. Restore fails without them.
COPY Directory.Packages.props global.json ./
COPY eShopOnWeb.sln Everything.sln ./
COPY src/ApplicationCore/ApplicationCore.csproj                     src/ApplicationCore/
COPY src/BlazorAdmin/BlazorAdmin.csproj                             src/BlazorAdmin/
COPY src/BlazorShared/BlazorShared.csproj                           src/BlazorShared/
COPY src/Infrastructure/Infrastructure.csproj                       src/Infrastructure/
COPY src/PublicApi/PublicApi.csproj                                 src/PublicApi/
COPY src/Web/Web.csproj                                             src/Web/
COPY src/eShopWeb.AspireServiceDefaults/eShopWeb.AspireServiceDefaults.csproj src/eShopWeb.AspireServiceDefaults/
COPY tests/UnitTests/UnitTests.csproj                               tests/UnitTests/
COPY tests/IntegrationTests/IntegrationTests.csproj                 tests/IntegrationTests/
COPY tests/FunctionalTests/FunctionalTests.csproj                   tests/FunctionalTests/
COPY tests/PublicApiIntegrationTests/PublicApiIntegrationTests.csproj tests/PublicApiIntegrationTests/

# Restore the web app + test projects (transitively covers ApplicationCore, Infrastructure,
# Blazor*, AspireServiceDefaults). No cache mount: packages must persist in the image layer.
RUN dotnet restore src/Web/Web.csproj \
 && dotnet restore tests/UnitTests/UnitTests.csproj \
 && dotnet restore tests/IntegrationTests/IntegrationTests.csproj \
 && dotnet restore tests/FunctionalTests/FunctionalTests.csproj \
 && dotnet restore tests/PublicApiIntegrationTests/PublicApiIntegrationTests.csproj

# curl is used by the runner's HTTP health-check stage. (git is present in the SDK image for
# the agent to diff/commit the bind-mounted working copy.)
RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

# The bind-mounted working copy is owned by the host user, not the container's root; without
# this git refuses with "dubious ownership". Allow git to operate on the mounted repo.
RUN git config --system --add safe.directory '*'

# The image carries no source — the host working copy is bind-mounted rw at /work at runtime,
# so agent edits land directly in the host repo (and never taint the image).
WORKDIR /work

# Idle by default; sandbox.sh exec's the bind-mounted runner into this container.
# (single canonical dispatcher; on Windows run sandbox.sh from WSL2)
CMD ["sleep", "infinity"]
