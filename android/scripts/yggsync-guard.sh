#!/data/data/com.termux/files/usr/bin/bash

RUNTIME_ENV="${YGG_CLIENT_RUNTIME_ENV:-$HOME/.config/ygg_client.env}"
if [[ -f "$RUNTIME_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"
  set +a
fi

YGG_REQUIRE_WIFI="${YGG_REQUIRE_WIFI:-1}"
YGG_MONITOR_INTERVAL_SECONDS="${YGG_MONITOR_INTERVAL_SECONDS:-20}"
YGG_HOST_CHECK_TIMEOUT_SECONDS="${YGG_HOST_CHECK_TIMEOUT_SECONDS:-3}"
YGG_TAILSCALE_BIN="${YGG_TAILSCALE_BIN:-tailscale}"
YGG_GUARD_DEFER_EXIT="${YGG_GUARD_DEFER_EXIT:-75}"

guard_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

json_get() {
  local key="$1"
  python3 - "$key" <<'PY'
import json
import sys

key = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
value = data.get(key, "")
if value is None:
    value = ""
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

battery_json() {
  if ! command -v termux-battery-status >/dev/null 2>&1; then
    return 1
  fi
  termux-battery-status 2>/dev/null
}

battery_field() {
  local key="$1" raw
  raw="$(battery_json || true)"
  [[ -n "$raw" ]] || return 1
  printf '%s' "$raw" | json_get "$key"
}

wifi_json() {
  if ! command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
    return 1
  fi
  termux-wifi-connectioninfo 2>/dev/null
}

wifi_field() {
  local key="$1" raw
  raw="$(wifi_json || true)"
  [[ -n "$raw" ]] || return 1
  printf '%s' "$raw" | json_get "$key"
}

current_ssid() {
  local ssid
  ssid="$(wifi_field ssid 2>/dev/null || true)"
  ssid="${ssid%\"}"
  ssid="${ssid#\"}"
  printf '%s' "$ssid"
}

wifi_connected() {
  local ssid ip
  ssid="$(current_ssid)"
  ip="$(wifi_field ip 2>/dev/null || true)"
  [[ -n "$ssid" || -n "$ip" ]]
}

tailscale_online() {
  if ! command -v "$YGG_TAILSCALE_BIN" >/dev/null 2>&1; then
    return 1
  fi
  "$YGG_TAILSCALE_BIN" status --json 2>/dev/null | python3 - <<'PY'
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
backend = data.get("BackendState", "")
self_info = data.get("Self", {})
online = self_info.get("Online", backend == "Running")
sys.exit(0 if backend == "Running" and online else 1)
PY
}

battery_ok() {
  local min_battery="$1" status pct
  status="$(battery_field status 2>/dev/null || true)"
  pct="$(battery_field percentage 2>/dev/null || true)"
  if [[ -z "$pct" ]]; then
    return 0
  fi
  if [[ "$status" == "CHARGING" || "$status" == "FULL" ]]; then
    return 0
  fi
  [[ "$pct" -ge "$min_battery" ]]
}

battery_temp_ok() {
  local max_temp="$1" temp
  temp="$(battery_field temperature 2>/dev/null || true)"
  if [[ -z "$temp" || -z "$max_temp" ]]; then
    return 0
  fi
  python3 - "$temp" "$max_temp" <<'PY'
import sys

try:
    temp = float(sys.argv[1])
    max_temp = float(sys.argv[2])
except Exception:
    sys.exit(0)
sys.exit(0 if temp <= max_temp else 1)
PY
}

job_hosts() {
  local config_path="$1" jobs_csv="$2"
  python3 - "$config_path" "$jobs_csv" <<'PY'
import sys
import tomllib

config_path = sys.argv[1]
jobs_csv = sys.argv[2]
with open(config_path, "rb") as fh:
    cfg = tomllib.load(fh)

targets = {t.get("name"): t for t in cfg.get("targets", []) if t.get("name")}
wanted = {j for j in jobs_csv.split(",") if j}
seen = set()

for job in cfg.get("jobs", []):
    name = job.get("name", "")
    if wanted and name not in wanted:
        continue
    remote = job.get("remote", "")
    if ":" not in remote:
        continue
    target_name, _ = remote.split(":", 1)
    target = targets.get(target_name)
    if not target or target.get("type") != "smb":
        continue
    host = target.get("host")
    port = int(target.get("port") or 445)
    key = (host, port)
    if host and key not in seen:
        seen.add(key)
        print(f"{host}\t{port}")
PY
}

host_reachable() {
  local host="$1" port="$2"
  python3 - "$host" "$port" "$YGG_HOST_CHECK_TIMEOUT_SECONDS" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
timeout = float(sys.argv[3])
try:
    with socket.create_connection((host, port), timeout=timeout):
        pass
except Exception:
    sys.exit(1)
PY
}

connectivity_ok() {
  local config_path="$1" jobs_csv="$2" failed=0 any=0 host port
  while IFS=$'\t' read -r host port; do
    [[ -n "$host" ]] || continue
    any=1
    if ! host_reachable "$host" "$port"; then
      guard_log "connectivity check failed: ${host}:${port} is unreachable"
      failed=1
    fi
  done < <(job_hosts "$config_path" "$jobs_csv")
  if [[ "$any" -eq 0 ]]; then
    return 0
  fi
  [[ "$failed" -eq 0 ]]
}

guard_preflight() {
  local config_path="$1" jobs_csv="$2" min_battery="$3" max_temp="$4"
  local ssid
  if ! battery_ok "$min_battery"; then
    guard_log "deferred: battery below ${min_battery}% and not charging"
    return 1
  fi
  if ! battery_temp_ok "$max_temp"; then
    guard_log "deferred: battery temperature above ${max_temp}C"
    return 1
  fi
  if [[ "$YGG_REQUIRE_WIFI" == "1" ]] && ! wifi_connected; then
    guard_log "deferred: Wi-Fi is not connected"
    return 1
  fi
  if ! connectivity_ok "$config_path" "$jobs_csv"; then
    ssid="$(current_ssid)"
    if tailscale_online; then
      guard_log "deferred: SMB host unreachable even though Tailscale is running${ssid:+ (ssid=${ssid})}"
    else
      guard_log "deferred: SMB host unreachable and Tailscale is off${ssid:+ (ssid=${ssid})}"
    fi
    return 1
  fi
  return 0
}

run_guarded_yggsync() {
  local config_path="$1" jobs_csv="$2" min_battery="$3" max_temp="$4"
  local pid status

  if ! guard_preflight "$config_path" "$jobs_csv" "$min_battery" "$max_temp"; then
    return "$YGG_GUARD_DEFER_EXIT"
  fi

  nice -n 10 "$YGG_BIN" -config "$config_path" -jobs "$jobs_csv" &
  pid=$!
  guard_log "started yggsync pid=${pid} jobs=${jobs_csv}"

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$YGG_MONITOR_INTERVAL_SECONDS"
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    if guard_preflight "$config_path" "$jobs_csv" "$min_battery" "$max_temp"; then
      continue
    fi
    guard_log "stopping yggsync pid=${pid} because runtime conditions changed"
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 2
    done
    if kill -0 "$pid" 2>/dev/null; then
      guard_log "forcing yggsync pid=${pid} to stop"
      kill -9 "$pid" 2>/dev/null || true
    fi
    wait "$pid" || true
    return "$YGG_GUARD_DEFER_EXIT"
  done

  wait "$pid"
  status=$?
  guard_log "yggsync pid=${pid} exited with status=${status}"
  return "$status"
}
