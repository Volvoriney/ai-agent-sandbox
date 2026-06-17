# Proposal: build-agent-sandbox

## Why

AI coding agents at the company take tickets and produce tested pull requests, but they have no isolated execution environment to clone, build, test, and validate code in without affecting other work or the host machine. This change delivers a Docker-based AI agent sandbox (interview task 003) that must prove itself against two real-world projects with conflicting stacks: eShopOnWeb (ASP.NET Core / SQL Server) and Medplum (TypeScript / PostgreSQL + Redis).

## What Changes

- New Docker-based sandbox infrastructure (Dockerfiles, docker-compose, orchestration scripts) capable of building and running two heterogeneous projects.
- Per-project compositions: eShopOnWeb (build, EF migrations, seed data, web app responding over HTTP, test suite) and Medplum (server build/start, DB migrations, API health checks, test suite).
- Sandbox lifecycle management: non-interactive spin-up, clean state reset between agent runs without full rebuilds, and teardown.
- Resource and isolation controls: memory/CPU limits, network boundaries, no host access from agent-executed code.
- Documentation: README explaining architecture decisions (one sandbox vs. two, database strategy, caching/startup strategy) and proof-of-work evidence.

## Capabilities

### New Capabilities
- `sandbox-lifecycle`: Spin-up, reset to clean state, and teardown of sandbox environments, fully non-interactive and repeatable.
- `project-eshoponweb`: Build, migrate, seed, run, and test eShopOnWeb inside the sandbox against SQL Server.
- `project-medplum`: Build, migrate, run, and test Medplum inside the sandbox against PostgreSQL and Redis.
- `output-capture`: Structured capture of build/test/health-check results for consumption by an automated pipeline.
- `isolation-and-resources`: Resource limits and security boundaries for executing untrusted agent-generated code.

### Modified Capabilities

(None — greenfield project, no existing specs.)

## Impact

- New repository content: `docker/` (Dockerfiles, compose files), `scripts/` (lifecycle + result-capture scripts), `README.md`.
- External dependencies: Docker Engine / Docker Compose, mcr.microsoft.com SQL Server image, postgres and redis images, .NET SDK and Node.js build images.
- Upstream repos consumed (not modified): github.com/NimblePros/eShopOnWeb, github.com/medplum/medplum.
- Resource footprint: SQL Server alone requires ~2 GB RAM; total sandbox budget must be planned (~6–8 GB for both stacks concurrently, less if run sequentially).
