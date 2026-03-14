#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

CONFIG="${YGG_SYNC_CONFIG:-$HOME/.config/ygg_sync.toml}"
YGG_BIN="${YGG_BIN:-$HOME/.local/bin/yggsync}"
LOG_DIR="$HOME/.local/state/ygg_client"
LOG_FILE="$LOG_DIR/sync-yggsync-fast.log"
JOBS="${JOBS:-obsidian,notes}"
MIN_BATTERY="${YGG_MIN_BATTERY_FAST:-50}"

mkdir -p "$LOG_DIR"

battery_ok() {
  if ! command -v termux-battery-status >/dev/null 2>&1; then
    return 0
  fi
  local status pct
  status="$(termux-battery-status 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status",""))' 2>/dev/null || true)"
  pct="$(termux-battery-status 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("percentage",""))' 2>/dev/null || true)"
  if [[ -z "$pct" ]]; then
    return 0
  fi
  if [[ "$status" == "CHARGING" || "$status" == "FULL" ]]; then
    return 0
  fi
  [[ -n "$pct" && "$pct" -ge "$MIN_BATTERY" ]]
}

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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] yggsync fast requested jobs: $JOBS"
  if ! battery_ok; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] skipped: battery below ${MIN_BATTERY}% and not charging"
    exit 0
  fi
  if [[ -z "$resolved_jobs" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] skipped: no configured fast jobs matched"
    exit 0
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] yggsync fast resolved jobs: $resolved_jobs"
  nice -n 10 "$YGG_BIN" -config "$CONFIG" -jobs "$resolved_jobs"
} >>"$LOG_FILE" 2>&1
