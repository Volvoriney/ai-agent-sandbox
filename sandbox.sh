#!/usr/bin/env bash
# Sandbox dispatcher (Linux/macOS; on Windows run from a WSL2 shell).
#
#   ./sandbox.sh setup [project]        clone pinned upstream sources into .upstream/
#   ./sandbox.sh up    <project>        start the persistent workspace + backing services
#   ./sandbox.sh run   <project>        exec the validation pipeline (build→…→test) into it
#   ./sandbox.sh exec  <project> <cmd…> run a command in the live workspace (agent iteration)
#   ./sandbox.sh shell <project>        interactive bash in the live workspace
#   ./sandbox.sh reset <project>        down -v && up  (clean state, NO image rebuild)
#   ./sandbox.sh down  <project>        full teardown (containers, network, volumes)
#
# project is one of: eshop | medplum   (the repo->composition mapping, design D1)
#
# Model: the app/build container is a PERSISTENT workspace (idles via the image's
# `sleep infinity`). An AI harness exec's into it to build/test/poke around across one task,
# then validates with `run` and tears down with `down`/`reset`. The agent works INSIDE; the
# host/control-plane owns lifecycle (no Docker socket inside the container — isolation).
#
# Logging: `run` captures the exec'd pipeline's stdout (incl. the app it launches) and tees it
# to results/<run-id>/run.log — the local stand-in for the harness's log capture / aggregator.
# The only artifacts the container writes are results.json + native test reports (TRX/jest).

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$ROOT/docker"

compose_file() {
  local f="$COMPOSE_DIR/compose.$1.yml"
  [ -f "$f" ] || { echo "Unknown project '$1' (no $f)" >&2; exit 2; }
  echo "$f"
}

app_service() { case "$1" in eshop) echo "eshop-app";; medplum) echo "medplum-server";; *) exit 2;; esac; }
require_project() { [ -n "${PROJECT:-}" ] || { echo "Verb '$VERB' requires a <project> (eshop|medplum)" >&2; exit 2; }; }

VERB="${1:-}"; PROJECT="${2:-}"

case "$VERB" in
  setup)
    "$ROOT/scripts/setup.sh" "${PROJECT:-all}"
    ;;
  up)
    require_project; cf="$(compose_file "$PROJECT")"
    echo "[sandbox] up: $PROJECT (workspace + backing services)"
    docker compose -f "$cf" up -d --build
    ;;
  down)
    require_project; cf="$(compose_file "$PROJECT")"
    echo "[sandbox] down: $PROJECT"
    docker compose -f "$cf" down -v --remove-orphans
    ;;
  reset)
    require_project; cf="$(compose_file "$PROJECT")"
    echo "[sandbox] reset: $PROJECT (down -v && up, no rebuild)"
    docker compose -f "$cf" down -v --remove-orphans
    docker compose -f "$cf" up -d            # no --build: reuse cached base image
    ;;
  exec)
    require_project; cf="$(compose_file "$PROJECT")"; svc="$(app_service "$PROJECT")"
    shift 2  # drop verb + project; remainder is the command
    [ "$#" -gt 0 ] || { echo "exec needs a command: sandbox.sh exec $PROJECT <cmd…>" >&2; exit 2; }
    docker compose -f "$cf" up -d >/dev/null   # ensure workspace is live (no rebuild)
    docker compose -f "$cf" exec "$svc" "$@"
    ;;
  shell)
    require_project; cf="$(compose_file "$PROJECT")"; svc="$(app_service "$PROJECT")"
    docker compose -f "$cf" up -d >/dev/null
    docker compose -f "$cf" exec "$svc" bash
    ;;
  run)
    require_project; cf="$(compose_file "$PROJECT")"; svc="$(app_service "$PROJECT")"
    run_id="$(date +%Y%m%d-%H%M%S)"; run_dir="$ROOT/results/$run_id"
    mkdir -p "$run_dir"
    ln -sfn "$run_id" "$ROOT/results/latest"   # stable path: agent reads results/latest/*
    echo "[sandbox] run: $PROJECT (run-id $run_id)"
    # Ensure the workspace is live WITHOUT --build: rebuilding yields a new image digest, which
    # recreates the container and discards /work (agent edits). Image is built by `up`/`reset`.
    docker compose -f "$cf" up -d

    # Exec the validation pipeline INTO the live workspace. Its stdout (incl. the app/server it
    # launches) is tee'd to run.log — captured OUTSIDE the container, so it survives a crash.
    set +e
    docker compose -f "$cf" exec -T -e "RUN_ID=$run_id" "$svc" bash /usr/local/bin/run-checks 2>&1 \
      | tee "$run_dir/run.log"
    runner_exit="${PIPESTATUS[0]}"
    set -e

    # Workspace is LEFT RUNNING so the agent can poke around (exec/shell) before teardown.

    # Exit-code guarantee: synthesize a failure envelope if the runner never wrote results.json.
    if [ ! -f "$run_dir/results.json" ]; then
      echo "[sandbox] runner produced no results.json — synthesizing failure envelope"
      printf '{\n  "schemaVersion":"1.0",\n  "project":"%s",\n  "runId":"%s",\n  "overall":"crashed",\n  "exitCode":%s,\n  "reason":"runner produced no result — container likely crashed/OOM-killed",\n  "log":"run.log"\n}\n' \
        "$PROJECT" "$run_id" "$runner_exit" > "$run_dir/results.json"
    fi

    echo "[sandbox] results: $run_dir (runner exit $runner_exit). Workspace still up — 'shell'/'exec' to poke, 'down'/'reset' when done."
    exit "$runner_exit"
    ;;
  *)
    echo "Usage: $0 {setup|up|run|exec|shell|reset|down} [eshop|medplum] [cmd…]" >&2
    exit 2
    ;;
esac
