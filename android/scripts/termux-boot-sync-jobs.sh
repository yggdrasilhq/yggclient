#!/data/data/com.termux/files/usr/bin/bash

# This script is intended to be run by Termux:Boot
# It re-registers the periodic sync job(s) using termux-job-scheduler.

# Location of the main yggclient repository.
SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_CLIENT_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_CLIENT_DIR="${YGG_CLIENT_DIR:-$YGG_CLIENT_DIR_DEFAULT}"
if [ ! -d "$YGG_CLIENT_DIR" ] && [ -d "$HOME/git/ygg_client" ]; then
  YGG_CLIENT_DIR="$HOME/git/ygg_client"
fi

# Log file for boot script actions
BOOT_LOG="$HOME/.local/state/ygg_client/termux-boot.log"
mkdir -p "$(dirname "$BOOT_LOG")"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Termux:Boot script started." >> "$BOOT_LOG"

# Wait a bit for network connectivity and Termux API to potentially establish
sleep 30

# --- Fast job (obsidian-only via yggsync) ---
JOB_ID_FAST=101
SCRIPT_FAST="$YGG_CLIENT_DIR/android/scripts/sync-yggsync-fast.sh"
chmod +x "$SCRIPT_FAST"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Scheduling fast yggsync job (ID: $JOB_ID_FAST)..." >> "$BOOT_LOG"
termux-job-scheduler --job-id $JOB_ID_FAST \
                     --script "$SCRIPT_FAST" \
                     --period-ms 3600000 \
                     --network unmetered \
                     --persisted true

# --- Bulk job (media/backup via yggsync) ---
JOB_ID_BULK=102
SCRIPT_BULK="$YGG_CLIENT_DIR/android/scripts/sync-yggsync-bulk.sh"
chmod +x "$SCRIPT_BULK"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Scheduling bulk yggsync job (ID: $JOB_ID_BULK)..." >> "$BOOT_LOG"
termux-job-scheduler --job-id $JOB_ID_BULK \
                     --script "$SCRIPT_BULK" \
                     --period-ms 21600000 \
                     --network unmetered \
                     --persisted true \
                     --battery-not-low true

echo "$(date '+%Y-%m-%d %H:%M:%S') - Sync jobs registration finished." >> "$BOOT_LOG"
