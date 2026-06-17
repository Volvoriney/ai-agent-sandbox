#!/usr/bin/env bash
# Clone pinned upstream sources into .upstream/<project>. Idempotent: skips existing checkouts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/pins.env"
PROJECT="${1:-all}"

clone() {
  local name="$1" repo="$2" ref="$3"
  local dest="$ROOT/.upstream/$name"
  if [ -d "$dest/.git" ]; then
    echo "[setup] $name already present at $dest — skipping (delete to re-clone)"
    return
  fi
  echo "[setup] cloning $name @ $ref"
  mkdir -p "$ROOT/.upstream"
  if [[ "$ref" == v* ]]; then
    git clone --depth 1 --branch "$ref" "$repo" "$dest"
  else
    git clone "$repo" "$dest"
    git -C "$dest" checkout "$ref"
  fi
}

case "$PROJECT" in
  eshop)   clone eshop "$ESHOP_REPO" "$ESHOP_REF" ;;
  medplum) clone medplum "$MEDPLUM_REPO" "$MEDPLUM_REF" ;;
  all)     clone eshop "$ESHOP_REPO" "$ESHOP_REF"; clone medplum "$MEDPLUM_REPO" "$MEDPLUM_REF" ;;
  *) echo "Unknown project '$PROJECT' (eshop|medplum|all)" >&2; exit 2 ;;
esac
echo "[setup] done"
