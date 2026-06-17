#!/usr/bin/env bash
# eShopOnWeb runner — exec'd into the persistent eshop-app workspace by `sandbox.sh run`.
# All output goes to the exec stdout, which the dispatcher tees to run.log. Stages:
# prepare -> build -> start -> healthcheck -> test.
#
# eShopOnWeb couples EF migrations + seed to APP STARTUP (Program.cs calls SeedDatabaseAsync
# before app.Run), so migrate+seed happen inside the `start` stage; a green `healthcheck`
# proves migrate+seed+serve all succeeded.

set -uo pipefail
export PROJECT="eshop"
source /usr/local/bin/results.sh
results_init

APP_URL="http://localhost:8080/"

# /work is the bind-mounted host clone (the agent's edits live here directly). No seed/copy:
# `run` validates the working copy as-is; source clean-state is harness-owned (git).

# 1) build — web app + test projects (offline-fast: NuGet baked into the base image)
run_stage build "dotnet build (Web + test projects)" -- bash -c '
  cd /work &&
  dotnet build src/Web/Web.csproj -c Release --nologo &&
  dotnet build tests/UnitTests/UnitTests.csproj -c Release --nologo &&
  dotnet build tests/FunctionalTests/FunctionalTests.csproj -c Release --nologo &&
  dotnet build tests/IntegrationTests/IntegrationTests.csproj -c Release --nologo
'

# 2) start — launch the web app DETACHED (setsid + </dev/null), inheriting the runner's
#    stdout so the app's logs land on the container stdout. The stage then waits for
#    readiness. The app applies EF migrations + seeds on boot, then serves.
#    --no-launch-profile: ignore launchSettings.json (forces https://localhost:5001 + dev cert).
# tee → stdout (captured by the dispatcher) AND app.log (so the in-sandbox agent can
# `tail -f /results/<run-id>/app.log` — it can't use `docker logs`, no host socket).
setsid bash -c "cd /work/src/Web && dotnet run -c Release --no-build --no-restore --no-launch-profile --project Web.csproj 2>&1 | tee /results/${RUN_ID:-local}/app.log" < /dev/null &
APP_PID=$!

run_stage start "wait for web app ready (EF migrate + seed on startup)" -- bash -c '
  for i in $(seq 1 90); do
    if ! kill -0 '"$APP_PID"' 2>/dev/null; then
      echo "[start] app process exited early"; exit 1
    fi
    if curl -fsS -o /dev/null "http://localhost:8080/"; then
      echo "[start] app is serving on :8080"; exit 0
    fi
    sleep 2
  done
  echo "[start] app did not become ready within timeout"; exit 1
'

# 3) healthcheck — explicit HTTP assertion: root must return a success status
run_stage healthcheck "HTTP GET / returns 2xx/3xx" -- bash -c '
  code=$(curl -s -o /dev/null -w "%{http_code}" "'"$APP_URL"'") &&
  echo "[healthcheck] HTTP $code" &&
  [ "$code" -ge 200 ] && [ "$code" -lt 400 ]
'

# 4) test — run the suite headlessly; TRX reports are ARTIFACTS written to the results dir
run_stage test "dotnet test (unit + functional + integration)" -- bash -c '
  cd /work
  rc=0
  for proj in UnitTests FunctionalTests IntegrationTests; do
    echo "[test] === $proj ==="
    dotnet test "tests/$proj/$proj.csproj" -c Release --no-build \
      --logger "trx;LogFileName=$proj.trx" \
      --results-directory "/results/'"${RUN_ID:-local}"'" || rc=1
  done
  exit $rc
'

# stop the app (best-effort; one-shot container exits after this anyway)
kill "$APP_PID" 2>/dev/null || true
pkill -f 'Web.csproj' 2>/dev/null || true

results_finalize
