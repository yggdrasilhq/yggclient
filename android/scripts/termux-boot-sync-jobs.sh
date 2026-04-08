#!/data/data/com.termux/files/usr/bin/bash

# This script is intended to be run by Termux:Boot
# It re-registers the periodic sync job(s) using termux-job-scheduler.

# Location of the main yggclient repository.
SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_CLIENT_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_CLIENT_DIR="${YGG_CLIENT_DIR:-$YGG_CLIENT_DIR_DEFAULT}"

# Log file for boot script actions
BOOT_LOG="$HOME/.local/state/ygg_client/termux-boot.log"
mkdir -p "$(dirname "$BOOT_LOG")"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Termux:Boot script started." >> "$BOOT_LOG"

AUTO_UPDATE="${YGG_AUTO_UPDATE:-1}"
UPDATE_SCRIPT="$YGG_CLIENT_DIR/android/scripts/update-public-stack.sh"

# Wait a bit for network connectivity and Termux API to potentially establish
sleep 30

if [[ "$AUTO_UPDATE" == "1" && -x "$UPDATE_SCRIPT" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Running auto-update step..." >> "$BOOT_LOG"
  bash "$UPDATE_SCRIPT" || echo "$(date '+%Y-%m-%d %H:%M:%S') - Auto-update step failed." >> "$BOOT_LOG"
fi

# --- Fast job (obsidian-only via yggsync) ---
JOB_ID_FAST=101
SCRIPT_FAST="$YGG_CLIENT_DIR/android/scripts/sync-yggsync-fast.sh"
FAST_PERIOD_MS="${YGG_FAST_PERIOD_MS:-10800000}"
chmod +x "$SCRIPT_FAST"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Scheduling fast yggsync job (ID: $JOB_ID_FAST)..." >> "$BOOT_LOG"
termux-job-scheduler --job-id $JOB_ID_FAST \
                     --script "$SCRIPT_FAST" \
                     --period-ms "$FAST_PERIOD_MS" \
                     --network unmetered \
                     --persisted true \
                     --battery-not-low true

# --- Bulk job (media/backup via yggsync) ---
JOB_ID_BULK=102
SCRIPT_BULK="$YGG_CLIENT_DIR/android/scripts/sync-yggsync-bulk.sh"
BULK_PERIOD_MS="${YGG_BULK_PERIOD_MS:-43200000}"
chmod +x "$SCRIPT_BULK"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Scheduling bulk yggsync job (ID: $JOB_ID_BULK)..." >> "$BOOT_LOG"
termux-job-scheduler --job-id $JOB_ID_BULK \
                     --script "$SCRIPT_BULK" \
                     --period-ms "$BULK_PERIOD_MS" \
                     --network unmetered \
                     --persisted true \
                     --battery-not-low true

echo "$(date '+%Y-%m-%d %H:%M:%S') - Sync jobs registration finished." >> "$BOOT_LOG"
