#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

YGGSYNC_BIN="${YGGSYNC_BIN:-${HOME}/.local/bin/yggsync}"
YGGSYNC_CONFIG="${YGGSYNC_CONFIG:-${HOME}/.config/ygg_sync.toml}"
JOBS="${JOBS:-screenshots-desktop,screencasts,downloads-to-nextcloud}"
EXTRA_ARGS=()

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if [[ -n "${DRY_RUN:-}" ]]; then
  EXTRA_ARGS+=("-dry-run")
fi
if [[ -n "${EXTRA_YGGSYNC_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS+=(${EXTRA_YGGSYNC_ARGS})
fi

if [[ ! -x "$YGGSYNC_BIN" ]]; then
  log "yggsync binary missing at ${YGGSYNC_BIN}. Hint: bash ${REPO_ROOT}/scripts/yggsync/fetch-yggsync.sh"
  exit 1
fi

if [[ ! -f "$YGGSYNC_CONFIG" ]]; then
  log "Config missing at ${YGGSYNC_CONFIG}. Copy the desktop template and adjust paths/remotes."
  exit 1
fi

cmd=("$YGGSYNC_BIN" -config "$YGGSYNC_CONFIG" -jobs "$JOBS")
cmd+=("${EXTRA_ARGS[@]}")

log "Running: ${cmd[*]}"
exec "${cmd[@]}"
