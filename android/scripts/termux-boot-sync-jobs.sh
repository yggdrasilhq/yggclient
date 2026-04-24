#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# This script is intended to be run by Termux:Boot
# It re-registers the periodic sync job(s) through yggsync itself.

# Location of the main yggclient repository.
SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_CLIENT_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_CLIENT_DIR="${YGG_CLIENT_DIR:-$YGG_CLIENT_DIR_DEFAULT}"
YGG_BIN="${YGG_BIN:-$HOME/.local/bin/yggsync}"
CONFIG="${YGG_SYNC_CONFIG:-$HOME/.config/ygg_sync.toml}"
RUNTIME="${YGG_SYNC_RUNTIME:-$HOME/.config/yggsync.runtime.toml}"

# Log file for boot script actions
BOOT_LOG="$HOME/.local/state/ygg_client/termux-boot.log"
mkdir -p "$(dirname "$BOOT_LOG")"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Termux:Boot script started." >> "$BOOT_LOG"

AUTO_UPDATE="${YGG_AUTO_UPDATE:-0}"
UPDATE_SCRIPT="$YGG_CLIENT_DIR/android/scripts/update-public-stack.sh"

# Wait a bit for network connectivity and Termux API to potentially establish
sleep 30

if [[ "$AUTO_UPDATE" == "1" && -x "$UPDATE_SCRIPT" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Running auto-update step..." >> "$BOOT_LOG"
  bash "$UPDATE_SCRIPT" || echo "$(date '+%Y-%m-%d %H:%M:%S') - Auto-update step failed." >> "$BOOT_LOG"
fi

OBSIDIAN_PERIOD_MS="${YGG_OBSIDIAN_PERIOD_MS:-${YGG_FAST_PERIOD_MS:-10800000}}"
BULK_PERIOD_MS="${YGG_BULK_PERIOD_MS:-43200000}"
if [ ! -x "$YGG_BIN" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - yggsync binary missing at $YGG_BIN" >> "$BOOT_LOG"
  exit 1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') - Reinstalling scheduled yggsync jobs..." >> "$BOOT_LOG"
"$YGG_BIN" android install-jobs \
  -config "$CONFIG" \
  -runtime "$RUNTIME" \
  -obsidian-period-ms "$OBSIDIAN_PERIOD_MS" \
  -bulk-period-ms "$BULK_PERIOD_MS" >> "$BOOT_LOG" 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') - Sync jobs registration finished." >> "$BOOT_LOG"
