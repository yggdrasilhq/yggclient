#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_CLIENT_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_CLIENT_DIR="${YGG_CLIENT_DIR:-$YGG_CLIENT_DIR_DEFAULT}"
BOOT_LOG="$HOME/.local/state/ygg_client/termux-boot.log"
LOCAL_BIN="$HOME/.local/bin"
YGGSYNC_TARGET_VERSION="${YGGSYNC_VERSION:-v0.2.2}"

log() {
  printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$BOOT_LOG"
}

if [[ ! -d "$YGG_CLIENT_DIR/.git" ]]; then
  log "Auto-update skipped: ${YGG_CLIENT_DIR} is not a git checkout."
  exit 0
fi

log "Auto-update: refreshing yggclient checkout."
if git -C "$YGG_CLIENT_DIR" pull --ff-only >>"$BOOT_LOG" 2>&1; then
  log "Auto-update: yggclient pull succeeded."
else
  log "Auto-update: yggclient pull failed; leaving existing checkout in place."
fi

if [[ -x "$YGG_CLIENT_DIR/android/scripts/fetch-yggsync.sh" ]]; then
  current_version=""
  if [[ -x "$LOCAL_BIN/yggsync" ]]; then
    current_version="$("$LOCAL_BIN/yggsync" -version 2>/dev/null | awk '{print $2}' || true)"
  fi
  if [[ "$current_version" == "${YGGSYNC_TARGET_VERSION#v}" ]]; then
    log "Auto-update: installed yggsync already matches ${YGGSYNC_TARGET_VERSION}; skipping fetch."
  else
    log "Auto-update: refreshing yggsync release binary to ${YGGSYNC_TARGET_VERSION}."
    mkdir -p "$LOCAL_BIN"
    if OUT="$LOCAL_BIN/yggsync" bash "$YGG_CLIENT_DIR/android/scripts/fetch-yggsync.sh" "$YGGSYNC_TARGET_VERSION" >>"$BOOT_LOG" 2>&1; then
      log "Auto-update: yggsync refresh succeeded."
    else
      log "Auto-update: yggsync refresh failed; keeping existing binary."
    fi
  fi
fi

chmod +x "$YGG_CLIENT_DIR/android/scripts/"*.sh "$YGG_CLIENT_DIR/android/shortcuts/"* >>"$BOOT_LOG" 2>&1 || true
for dir in "$HOME/.shortcuts/tasks" "$HOME/.termux/widget/dynamic_shortcuts"; do
  mkdir -p "$dir"
  cp -f "$YGG_CLIENT_DIR/android/shortcuts/"* "$dir"/ >>"$BOOT_LOG" 2>&1 || true
  chmod +x "$dir"/* >>"$BOOT_LOG" 2>&1 || true
done

log "Auto-update: shortcut refresh complete."
