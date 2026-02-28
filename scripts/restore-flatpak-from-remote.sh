#!/usr/bin/env bash
set -euo pipefail

# Pull flatpak data from the smbfs backup back onto this host (copy-only).
# Layout mirrors root so you can drop home/ into $HOME and system bits into /var and /etc.
# 
# Env toggles:
#   REMOTE_BASE      smb rclone remote/path (default: smb0:data/smbfs/dada/flatpak)
#   RCLONE_BIN       rclone binary (default: rclone)
#   RCLONE_CONFIG    path to rclone config (default: ~/.config/rclone/rclone.conf)
#   INCLUDE_SYSTEM   set to 1 to also restore /var/lib/flatpak and /etc/flatpak (requires root)
#   USE_SUDO         set to 1 to prefix rclone with sudo for system paths

REMOTE_BASE_DEFAULT="smb0:data/smbfs/dada/flatpak"
REMOTE_BASE="${REMOTE_BASE:-${1:-$REMOTE_BASE_DEFAULT}}"
RCLONE_BIN="${RCLONE_BIN:-rclone}"
RCLONE_CONFIG="${RCLONE_CONFIG:-${HOME}/.config/rclone/rclone.conf}"
INCLUDE_SYSTEM="${INCLUDE_SYSTEM:-0}"
USE_SUDO="${USE_SUDO:-0}"

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: ${0##*/} [REMOTE_BASE]
  REMOTE_BASE defaults to ${REMOTE_BASE_DEFAULT}

Env toggles:
  REMOTE_BASE    Override remote path (same as positional)
  RCLONE_BIN     rclone binary (default: rclone)
  RCLONE_CONFIG  path to rclone config (default: ~/.config/rclone/rclone.conf)
  INCLUDE_SYSTEM Set to 1 to restore /var/lib/flatpak and /etc/flatpak (root needed)
  USE_SUDO       Set to 1 to prefix rclone with sudo for system paths
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -eq 0 ]]; then
  usage
fi

if [[ ! -f "$RCLONE_CONFIG" ]]; then
  die "rclone config missing at ${RCLONE_CONFIG}"
fi

build_cmd() {
  local src="$1" dest="$2" wantsudo="$3"
  local cmd=("$RCLONE_BIN" --config "$RCLONE_CONFIG" copy "$src" "$dest" --create-empty-src-dirs --fast-list --use-json-log --stats=30s)
  if [[ "$wantsudo" == "1" ]]; then
    cmd=(sudo "${cmd[@]}")
  fi
  printf '%s\0' "${cmd[@]}"
}

run_copy() {
  local src="$1" dest="$2" wantsudo="$3"
  log "Copying ${src} -> ${dest}"
  IFS=$'\0' read -r -d '' -a cmd < <(build_cmd "$src" "$dest" "$wantsudo")
  "${cmd[@]}"
}

run_copy "${REMOTE_BASE}/home/.config" "${HOME}/.config" "0"
run_copy "${REMOTE_BASE}/home/.local/share" "${HOME}/.local/share" "0"
run_copy "${REMOTE_BASE}/home/.local/state" "${HOME}/.local/state" "0"
run_copy "${REMOTE_BASE}/home/.var" "${HOME}/.var" "0"

if [[ "$INCLUDE_SYSTEM" == "1" ]]; then
  run_copy "${REMOTE_BASE}/var/lib/flatpak" "/var/lib/flatpak" "${USE_SUDO}"
  run_copy "${REMOTE_BASE}/etc/flatpak" "/etc/flatpak" "${USE_SUDO}"
else
  log "Skipping system paths; set INCLUDE_SYSTEM=1 (and USE_SUDO=1 if not root) to restore /var and /etc."
fi

log "Flatpak restore complete."
