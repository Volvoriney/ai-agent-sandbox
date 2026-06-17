#!/usr/bin/env bash
# Medplum runner — exec'd into the persistent medplum-server workspace by `sandbox.sh run`.
# All output goes to the exec stdout, which the dispatcher tees to run.log. Stages:
# build -> start -> healthcheck -> migrate-testdb -> test.
#
# Medplum runs DB migrations automatically on server startup (config.database.runMigrations
# defaults true), so migrate happens inside the `start` stage; a green `healthcheck` proves
# build + migrate + serve all succeeded.

set -uo pipefail
export PROJECT="medplum"
source /usr/local/bin/results.sh
results_init

CONFIG="file:/config/medplum.config.json"
HEALTH="http://localhost:8103/healthcheck"

# 1) build — server + its workspace deps (Turborepo cache makes this fast when unchanged)
run_stage build "turbo build @medplum/server" -- bash -c "
  cd /usr/src/medplum && npx turbo run build --filter=@medplum/server
"

# 2) start — launch the server DETACHED (setsid + </dev/null), inheriting the runner's stdout
#    so server logs land on the container stdout. Then wait for readiness. The server
#    auto-runs DB migrations on startup.
# tee → stdout (captured by the dispatcher) AND server.log (so the in-sandbox agent can
# `tail -f /results/<run-id>/server.log` — it can't use `docker logs`, no host socket).
setsid bash -c "cd /usr/src/medplum && node packages/server/dist/index.js '$CONFIG' 2>&1 | tee /results/${RUN_ID:-local}/server.log" < /dev/null &
SERVER_PID=$!

run_stage start "wait for server ready (auto-migrate on startup)" -- bash -c '
  for i in $(seq 1 120); do
    if ! kill -0 '"$SERVER_PID"' 2>/dev/null; then
      echo "[start] server process exited early"; exit 1
    fi
    if curl -fsS -o /dev/null "'"$HEALTH"'"; then
      echo "[start] server is serving on :8103"; exit 0
    fi
    sleep 2
  done
  echo "[start] server did not become ready within timeout"; exit 1
'

# 3) healthcheck — explicit assertion that /healthcheck returns success
run_stage healthcheck "HTTP GET /healthcheck returns 2xx" -- bash -c '
  code=$(curl -s -o /tmp/health.json -w "%{http_code}" "'"$HEALTH"'") &&
  echo "[healthcheck] HTTP $code" && cat /tmp/health.json && echo &&
  [ "$code" -ge 200 ] && [ "$code" -lt 300 ]
'

# 4) migrate-testdb — loadTestConfig() forces runMigrations=false against an empty medplum_test,
#    so migrate its schema first via a short-lived server on port 8203 (detached, stdout), then
#    wait + stop it.
setsid bash -c "cd /usr/src/medplum && exec node packages/server/dist/index.js file:/config/medplum.testdb.config.json" < /dev/null &
TESTDB_PID=$!

run_stage migrate-testdb "migrate medplum_test schema" -- bash -c '
  for i in $(seq 1 120); do
    if ! kill -0 '"$TESTDB_PID"' 2>/dev/null; then echo "[migrate-testdb] instance died"; exit 1; fi
    if curl -fsS -o /dev/null "http://localhost:8203/healthcheck"; then echo "[migrate-testdb] medplum_test migrated"; exit 0; fi
    sleep 2
  done
  echo "[migrate-testdb] timed out"; exit 1
'
kill "$TESTDB_PID" 2>/dev/null || true
pkill -f 'medplum.testdb.config.json' 2>/dev/null || true

# 5) test — @medplum/server jest suite. JSON report is an ARTIFACT written to the results dir.
#    SCOPE CUT (recorded in results.json): server package, healthcheck suite only — the full
#    monorepo suite exceeds the sandbox time budget (spec project-medplum).
#    loadTestConfig() reads POSTGRES_HOST from env and Redis from medplum.config.json, so we
#    set POSTGRES_HOST and repoint the package's medplum.config.json Redis at the service.
run_stage test "jest @medplum/server (scoped)" -- bash -c '
  cd /usr/src/medplum/packages/server &&
  node -e "const f=\"medplum.config.json\";const c=require(\"./\"+f);c.redis.host=\"redis\";require(\"fs\").writeFileSync(f,JSON.stringify(c,null,2));" &&
  POSTGRES_HOST=postgres POSTGRES_PORT=5432 \
  npx jest src/healthcheck.test.ts \
    --json --outputFile="/results/'"${RUN_ID:-local}"'/jest-server.json" \
    --runInBand
'

# stop the server (best-effort; one-shot container exits after this anyway)
kill "$SERVER_PID" 2>/dev/null || true
pkill -f 'packages/server/dist/index.js' 2>/dev/null || true

results_finalize '"testScope":"server package, healthcheck suite only (full monorepo suite cut for time budget — spec project-medplum)"'
