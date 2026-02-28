#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

CONFIG="${YGG_SYNC_CONFIG:-$HOME/.config/ygg_sync.toml}"
YGG_BIN="${YGG_BIN:-$HOME/.local/bin/yggsync}"
LOG_DIR="$HOME/.local/state/ygg_client"
LOG_FILE="$LOG_DIR/sync-yggsync-bulk.log"
# Default bulk jobs: everything except obsidian
JOBS="${JOBS:-whatsapp-backups,whatsapp-media,dcim,screenshots,cubecallacr,androidfs}"

mkdir -p "$LOG_DIR"
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] yggsync bulk jobs: $JOBS"
  "$YGG_BIN" -config "$CONFIG" -jobs "$JOBS"
} >>"$LOG_FILE" 2>&1
