#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

CONFIG="${YGG_SYNC_CONFIG:-$HOME/.config/ygg_sync.toml}"
YGG_BIN="${YGG_BIN:-$HOME/.local/bin/yggsync}"
LOG_DIR="$HOME/.local/state/ygg_client"
LOG_FILE="$LOG_DIR/sync-yggsync-fast.log"
JOBS="${JOBS:-obsidian}"

mkdir -p "$LOG_DIR"
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] yggsync fast jobs: $JOBS"
  "$YGG_BIN" -config "$CONFIG" -jobs "$JOBS"
  # Lightweight one-way check against remote to surface missing files (size-only)
  if command -v rclone >/dev/null 2>&1; then
    rclone check "$HOME/storage/shared/Documents/obsidian" smb0:data/smbfs/dada/obsidian --one-way --size-only --exclude "**/.obsidian/**"
  fi
} >>"$LOG_FILE" 2>&1
