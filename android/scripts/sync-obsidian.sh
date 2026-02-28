#!/data/data/com.termux/files/usr/bin/bash

# --- Configuration ---
REMOTE_NAME="smb0" # Must match the name used in `rclone config`
REMOTE_PATH="data/obsidian"  # Path *within* the SMB share configured in rclone
LOCAL_PATH="$HOME/storage/shared/Documents/obsidian"
STATE_DIR="$HOME/.local/state/ygg_client"
LOG_FILE="$STATE_DIR/sync-obsidian.log"
LOCK_FILE="$STATE_DIR/sync-obsidian.lock"
RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf" # Explicitly point to config

# --- Argument Parsing ---
VERBOSE_MODE=false
RCLONE_RESYNC_FLAG="" # Default to no resync flag

# Loop through all arguments passed to the script
for arg in "$@"
do
    case $arg in
        --verbose)
        VERBOSE_MODE=true
        shift # Remove --verbose from processing
        ;;
        --resync)
        RCLONE_RESYNC_FLAG="--resync"
        shift # Remove --resync from processing
        ;;
        *)
        # Handle other arguments or ignore unknown ones
        ;;
    esac
done

# --- Ensure directories exist ---
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$LOCAL_PATH" # Ensure local Obsidian directory exists

# --- Logging function ---
log_msg() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - sync-obsidian - $1" >> "$LOG_FILE"
}

# --- Pre-checks ---
if [ ! -f "$RCLONE_CONFIG" ]; then
    log_msg "ERROR: rclone config file not found at $RCLONE_CONFIG. Cannot sync."
    if [ "$VERBOSE_MODE" = true ]; then termux-toast -b red -c white "Obsidian Sync ERROR: rclone config missing!"; fi
    exit 1
fi
if ! command -v termux-wifi-connectioninfo &> /dev/null; then
    log_msg "WARNING: termux-wifi-connectioninfo command not found (Termux:API issue?). Cannot check network type. Proceeding anyway."
fi

# --- Basic Locking ---
if mkdir "$LOCK_FILE" 2>/dev/null; then
  trap 'rmdir "$LOCK_FILE" 2>/dev/null; log_msg "Sync script finished or interrupted."; exit' INT TERM EXIT
  log_msg "Lock acquired. Starting Obsidian sync (Resync: ${RCLONE_RESYNC_FLAG:-'false'})." # Log if resync is active
else
  if find "$LOCK_FILE" -type d -mmin +120 -print -exec rmdir {} \; 2>/dev/null; then
     log_msg "Removed stale lock file older than 2 hours. Proceeding."
     if mkdir "$LOCK_FILE" 2>/dev/null; then
         trap 'rmdir "$LOCK_FILE" 2>/dev/null; log_msg "Sync script finished or interrupted."; exit' INT TERM EXIT
         log_msg "Lock acquired after removing stale lock. Starting Obsidian sync (Resync: ${RCLONE_RESYNC_FLAG:-'false'})."
     else
         log_msg "Failed to acquire lock immediately after removing stale lock. Skipping."
         if [ "$VERBOSE_MODE" = true ]; then termux-toast "Obsidian sync skipped: Could not acquire lock."; fi
         exit 1
     fi
  else
      log_msg "Sync already in progress (lock file exists and is recent). Skipping."
      if [ "$VERBOSE_MODE" = true ]; then termux-toast "Obsidian sync skipped: Already running."; fi
      exit 1
  fi
fi

# --- Check Network ---
if command -v termux-wifi-connectioninfo &> /dev/null; then
    termux-wifi-connectioninfo > /dev/null 2>&1
    wifi_check_exit_code=$?
    if [ $wifi_check_exit_code -ne 0 ]; then
        log_msg "Not connected to Wi-Fi. Skipping sync."
        if [ "$VERBOSE_MODE" = true ]; then termux-toast "Obsidian sync skipped: Not on Wi-Fi."; fi
        exit 0 # Exit gracefully
    else
        log_msg "Network check passed: Connected to Wi-Fi."
    fi
else
    log_msg "Skipping network check as termux-wifi-connectioninfo is not available."
fi


# --- Run rclone bisync ---
log_msg "Executing: rclone bisync $RCLONE_RESYNC_FLAG $REMOTE_NAME:$REMOTE_PATH $LOCAL_PATH --verbose --log-file=$LOG_FILE --create-empty-src-dirs --config=$RCLONE_CONFIG --fast-list --retries 3 --low-level-retries 10"

# Execute rclone, including the $RCLONE_RESYNC_FLAG (which is either "--resync" or empty)
run_bisync(){
  timeout 1800 rclone bisync $1 "$REMOTE_NAME:$REMOTE_PATH" "$LOCAL_PATH" \
      --verbose \
      --log-file="$LOG_FILE" \
      --create-empty-src-dirs \
      --config="$RCLONE_CONFIG" \
      --fast-list \
      --retries 3 \
      --low-level-retries 10
  return $?
}

run_bisync "$RCLONE_RESYNC_FLAG"
sync_exit_code=$?

# Auto-recover once with --resync if we hit bisync fatal (7) without having requested resync
if [ $sync_exit_code -eq 7 ] && [ -z "$RCLONE_RESYNC_FLAG" ]; then
    log_msg "Bisync failed with code 7; retrying once with --resync"
    run_bisync "--resync"
    sync_exit_code=$?
fi

# --- Handle Exit Codes ---
if [ $sync_exit_code -eq 124 ]; then
    log_msg "Obsidian sync TIMED OUT after 30 minutes."
    if [ "$VERBOSE_MODE" = true ]; then termux-toast -b orange -c white "Obsidian sync TIMED OUT!"; fi
elif [ $sync_exit_code -eq 0 ]; then
  log_msg "Obsidian sync completed successfully."
  if [ "$VERBOSE_MODE" = true ]; then termux-toast "Obsidian synced successfully"; fi
elif [ $sync_exit_code -eq 9 ]; then
    log_msg "Obsidian bisync check complete. No changes needed or sync successful."
    if [ "$VERBOSE_MODE" = true ]; then termux-toast "Obsidian sync: No changes"; fi
# --- Special handling for exit code 7 ---
elif [ $sync_exit_code -eq 7 ]; then
    log_msg "Obsidian sync FAILED with critical error (Code: 7). Potential data loss or conflict detected. Manual resync likely required."
    if [ "$VERBOSE_MODE" = true ]; then termux-toast -b red -c white "Obsidian sync ERROR (Code 7): Resync needed!"; fi
    # Consider adding instructions here if not verbose? Maybe not, rely on manual check.
else
  log_msg "Obsidian sync failed with exit code $sync_exit_code. Check log for details."
  if [ "$VERBOSE_MODE" = true ]; then termux-toast -b red -c white "Obsidian sync FAILED (Code: $sync_exit_code)"; fi
fi

# --- Cleanup ---
if [ -f "$LOG_FILE" ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

exit $sync_exit_code
