#!/usr/bin/env bash
# Propose the canonical V6 deployment while persisting the DEFIFA revnet start
# anchor needed by post-deploy address dumping and verification.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <testnets|mainnets>" >&2
  exit 2
fi

NETWORKS="$1"
case "$NETWORKS" in
  testnets|mainnets) ;;
  *)
    echo "error: unsupported networks '$NETWORKS' (expected testnets or mainnets)" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$SCRIPT_DIR/post-deploy/.cache"

DEFAULT_DEFIFA_REV_START_DELAY_SECONDS=604800 # 7 days
MIN_DEFIFA_REV_START_LEAD_SECONDS=259200 # 3 days

START_TIME="${DEFIFA_REV_START_TIME:-}"
NOW="$(date +%s)"
if [[ -z "$START_TIME" ]]; then
  START_TIME=$((NOW + DEFAULT_DEFIFA_REV_START_DELAY_SECONDS))
fi

if ! [[ "$START_TIME" =~ ^[0-9]+$ ]]; then
  echo "error: DEFIFA_REV_START_TIME must be a unix timestamp, got '$START_TIME'" >&2
  exit 2
fi

if (( START_TIME <= NOW )); then
  echo "error: DEFIFA_REV_START_TIME must be in the future for a new proposal" >&2
  exit 2
fi

MIN_START_TIME=$((NOW + MIN_DEFIFA_REV_START_LEAD_SECONDS))
if (( START_TIME < MIN_START_TIME )); then
  echo "error: DEFIFA_REV_START_TIME must be at least ${MIN_DEFIFA_REV_START_LEAD_SECONDS}s in the future" >&2
  echo "       Pick a timestamp far enough out for Safe approvals and Sphinx execution." >&2
  exit 2
fi

echo "Pinned DEFIFA_REV_START_TIME=$START_TIME"

cd "$DEPLOY_ROOT"
DEFIFA_REV_START_TIME="$START_TIME" npx sphinx propose script/Deploy.s.sol --networks "$NETWORKS"

mkdir -p "$CACHE_DIR"
printf 'DEFIFA_REV_START_TIME=%s\n' "$START_TIME" > "$CACHE_DIR/defifa-rev-start-time-${NETWORKS}.env"
printf 'DEFIFA_REV_START_TIME=%s\n' "$START_TIME" > "$CACHE_DIR/defifa-rev-start-time.env"
echo "Cached DEFIFA_REV_START_TIME in $CACHE_DIR/defifa-rev-start-time-${NETWORKS}.env"
