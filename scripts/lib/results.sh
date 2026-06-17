#!/usr/bin/env bash
# Shared structured-output helpers (output-capture spec / design D4).
#
# Logging model: the runner + the app it launches write everything to STDOUT/STDERR. The
# runner is exec'd into the workspace, so that stream reaches the dispatcher (the exec client),
# which tees it to results/<run-id>/run.log — the local stand-in for the harness's log
# capture / aggregator (Loki/CloudWatch/Splunk) in production.
# The runner itself writes only ARTIFACTS to the bind-mounted results dir:
#   - results.json          structured per-stage verdict (status/exitCode/duration, overall)
#   - native test reports    TRX (dotnet) / jest JSON — written by the test stages
# The dispatcher owns the exit-code guarantee and synthesizes a failure envelope if this
# runner dies before writing results.json.
#
# Usage:
#   export PROJECT=eshop RUN_ID=...
#   source /usr/local/bin/results.sh
#   results_init
#   run_stage <name> "<human label>" -- <command...>
#   results_finalize ['"extraKey":"value"']   # returns 0 iff overall passed

set -uo pipefail

RESULTS_DIR="/results/${RUN_ID:-local}"
PROJECT="${PROJECT:-unknown}"
_STAGES_JSON=""
_OVERALL_FAILED=0

results_init() {
  mkdir -p "$RESULTS_DIR"   # holds artifacts only (results.json + native test reports)
  _STAGES_JSON=""
  _OVERALL_FAILED=0
  echo "[sandbox] project=$PROJECT run_id=${RUN_ID:-local} (logs -> stdout, artifacts -> $RESULTS_DIR)"
}

# run_stage <name> <label> -- <command...>
# Streams the command's output to stdout (captured by the log driver). No per-stage files.
run_stage() {
  local name="$1"; shift
  local label="$1"; shift
  [ "${1:-}" = "--" ] && shift
  local status exit_code dur start end

  if [ "$_OVERALL_FAILED" -ne 0 ]; then
    status="skipped"; exit_code="null"; dur=0
    echo "[sandbox] SKIP  $name — previous stage failed"
  else
    echo "[sandbox] ===== $name: $label ====="
    start=$(date +%s)
    "$@"
    exit_code=$?
    end=$(date +%s); dur=$((end - start))
    if [ "$exit_code" -eq 0 ]; then
      status="passed"
    else
      status="failed"; _OVERALL_FAILED=1
    fi
    echo "[sandbox] ----- $name: $status (${dur}s, exit ${exit_code}) -----"
  fi

  local frag
  frag=$(printf '{"name":"%s","label":"%s","status":"%s","exitCode":%s,"durationSec":%s}' \
    "$name" "$label" "$status" "$exit_code" "$dur")
  _STAGES_JSON="${_STAGES_JSON:+$_STAGES_JSON,}$frag"
}

# results_finalize [extra-json-fields]
results_finalize() {
  local overall="passed"
  [ "$_OVERALL_FAILED" -ne 0 ] && overall="failed"
  local extra="${1:-}"
  {
    echo "{"
    echo "  \"schemaVersion\": \"1.0\","
    echo "  \"project\": \"$PROJECT\","
    echo "  \"runId\": \"${RUN_ID:-local}\","
    echo "  \"overall\": \"$overall\","
    [ -n "$extra" ] && echo "  $extra,"
    echo "  \"stages\": [${_STAGES_JSON}]"
    echo "}"
  } > "$RESULTS_DIR/results.json"
  echo "[sandbox] wrote $RESULTS_DIR/results.json (overall=$overall)"
  [ "$overall" = "passed" ]
}
