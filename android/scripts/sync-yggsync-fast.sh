#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

CONFIG="${YGG_SYNC_CONFIG:-$HOME/.config/ygg_sync.toml}"
YGG_BIN="${YGG_BIN:-$HOME/.local/bin/yggsync}"
LOG_DIR="$HOME/.local/state/ygg_client"
LOG_FILE="$LOG_DIR/sync-yggsync-fast.log"
JOBS="${JOBS:-obsidian,notes}"
MIN_BATTERY="${YGG_MIN_BATTERY_FAST:-50}"
MAX_TEMP="${YGG_MAX_BATTERY_TEMP_FAST_C:-39.5}"
SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$LOG_DIR"

# shellcheck source=android/scripts/yggsync-guard.sh
source "$SCRIPT_DIR_SELF/yggsync-guard.sh"

resolve_jobs() {
  local wanted raw job present=()
  raw="$("$YGG_BIN" -config "$CONFIG" -list 2>/dev/null || true)"
  for wanted in ${JOBS//,/ }; do
    if printf '%s\n' "$raw" | grep -qx "$wanted"; then
      present+=("$wanted")
    fi
  done
  (IFS=,; printf '%s' "${present[*]}")
}

{
  resolved_jobs="$(resolve_jobs)"
  guard_log "yggsync fast requested jobs: $JOBS"
  if [[ -z "$resolved_jobs" ]]; then
    guard_log "skipped: no configured fast jobs matched"
    exit 0
  fi
  guard_log "yggsync fast resolved jobs: $resolved_jobs"
  run_guarded_yggsync "$CONFIG" "$resolved_jobs" "$MIN_BATTERY" "$MAX_TEMP"
} >>"$LOG_FILE" 2>&1
