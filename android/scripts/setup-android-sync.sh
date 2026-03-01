#!/data/data/com.termux/files/usr/bin/bash

echo "Starting Yggdrasil Client Android Sync Setup..."

# --- Variables ---
SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_CLIENT_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_CLIENT_DIR="${YGG_CLIENT_DIR:-$YGG_CLIENT_DIR_DEFAULT}"
BOOT_SCRIPT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT_NAME="ygg-start-sync-jobs"
BOOT_SCRIPT_PATH="$BOOT_SCRIPT_DIR/$BOOT_SCRIPT_NAME"
TERMUX_BOOT_SETUP_SCRIPT="$YGG_CLIENT_DIR/android/scripts/termux-boot-sync-jobs.sh"
RCLONE_CONFIG_DIR="$HOME/.config/rclone"
RCLONE_CONFIG_FILE="$RCLONE_CONFIG_DIR/rclone.conf"
RCLONE_CONFIG_TEMPLATE="$YGG_CLIENT_DIR/android/config/rclone/rclone.conf.template"
STATE_DIR="$HOME/.local/state/ygg_client"
BOOTSTRAP_SCRIPT="$YGG_CLIENT_DIR/android/scripts/bootstrap.sh"
# --- Shortcut Variables ---
SHORTCUTS_DIR_SRC="$YGG_CLIENT_DIR/android/shortcuts"
# Target for home screen widgets, using recommended 'tasks' subdirectory
SHORTCUTS_DIR_TARGET_WIDGET="$HOME/.shortcuts"
SHORTCUTS_DIR_TARGET_WIDGET_TASKS="$SHORTCUTS_DIR_TARGET_WIDGET/tasks"
# Target for app long-press dynamic shortcuts
DYNAMIC_SHORTCUTS_DIR_TARGET="$HOME/.termux/widget/dynamic_shortcuts"

# --- Prerequisites Check ---
echo "Checking prerequisites..."
# Updated error messages to point to the correct bootstrap script path
command -v rclone >/dev/null 2>&1 || { echo >&2 "ERROR: rclone not found. Run 'bash $BOOTSTRAP_SCRIPT'. Aborting."; exit 1; }
command -v termux-job-scheduler >/dev/null 2>&1 || { echo >&2 "ERROR: termux-api commands not found. Run 'bash $BOOTSTRAP_SCRIPT' and ensure Termux:API app is installed/running. Aborting."; exit 1; }
command -v termux-setup-storage >/dev/null 2>&1 || { echo >&2 "ERROR: termux-setup-storage not found? Should be part of Termux base. Aborting."; exit 1; }
[ -d "$HOME/storage/shared" ] || { echo >&2 "ERROR: ~/storage/shared not found. Run 'termux-setup-storage' and grant permission via the Android popup. Aborting."; exit 1; }
[ -d "$YGG_CLIENT_DIR" ] || { echo >&2 "ERROR: Yggdrasil client directory not found at $YGG_CLIENT_DIR. Clone the repo first. Aborting."; exit 1; }
[ -f "$BOOTSTRAP_SCRIPT" ] || { echo >&2 "ERROR: Bootstrap script not found at $BOOTSTRAP_SCRIPT. Ensure repo is cloned correctly. Aborting."; exit 1; }


# --- Ensure State Directory Exists ---
mkdir -p "$STATE_DIR"
echo "State directory ensured at $STATE_DIR"

# --- rclone Configuration Check ---
# (No changes needed in this section)
echo "Checking rclone configuration..."
if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
    echo "WARNING: rclone config file ($RCLONE_CONFIG_FILE) not found."
    if [ -f "$RCLONE_CONFIG_TEMPLATE" ]; then
        echo "Template found at $RCLONE_CONFIG_TEMPLATE."
        echo "Please run 'rclone config' interactively in Termux to set up your smb0 remote."
        echo "Refer to the template or README for details."
    else
        echo "No template found either. Please run 'rclone config' interactively."
    fi
    read -p "Run 'rclone config' now? (y/N): " run_rclone_now
    if [[ "$run_rclone_now" =~ ^[Yy]$ ]]; then
        rclone config
        # Re-check after running
        if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
            echo >&2 "ERROR: rclone config file still not found after running command. Aborting setup."
            exit 1
        fi
         echo "rclone config created. Continuing setup..."
    else
        echo >&2 "Aborting setup. rclone configuration is required."
        exit 1
    fi
else
    echo "rclone config file found: $RCLONE_CONFIG_FILE"
    # Optional: Check if the specific remote exists
    if ! rclone listremotes --config "$RCLONE_CONFIG_FILE" | grep -q "^smb0:"; then
       echo >&2 "WARNING: 'smb0:' remote not found in rclone config ($RCLONE_CONFIG_FILE)."
       echo >&2 "The sync script will fail unless you add it using 'rclone config'."
       read -p "Continue setup anyway? (y/N): " continue_anyway
       if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
           echo "Aborting setup."
           exit 1
       fi
    else
        echo "'smb0:' remote found in config."
    fi
fi

# --- Make sync scripts executable ---
echo "Making scripts executable..."
chmod +x "$YGG_CLIENT_DIR/android/scripts/sync-obsidian.sh"
chmod +x "$TERMUX_BOOT_SETUP_SCRIPT"
chmod +x "$BOOTSTRAP_SCRIPT" # Ensure bootstrap is executable too

# --- Make core scripts executable ---
echo "Making core scripts executable..."
chmod +x "$YGG_CLIENT_DIR/android/scripts/"*.sh # Make all scripts in android/scripts executable

# --- Setup Termux:Boot ---
echo "Setting up Termux:Boot script..."
mkdir -p "$BOOT_SCRIPT_DIR"
cat > "$BOOT_SCRIPT_PATH" <<- EOM
#!/data/data/com.termux/files/usr/bin/bash
# This script is executed by Termux:Boot on device startup.
# It calls the main job registration script from the git repo.

# Execute the actual setup script from the repository
bash "$TERMUX_BOOT_SETUP_SCRIPT"
EOM
chmod +x "$BOOT_SCRIPT_PATH"
echo "Termux:Boot script created/updated at $BOOT_SCRIPT_PATH"
echo "Ensure the Termux:Boot app is installed and enabled."

# --- Setup Termux:Widget Shortcuts (Copying for Home Screen Widgets) ---
echo "Setting up Termux:Widget home screen shortcuts (copies)..."
mkdir -p "$SHORTCUTS_DIR_TARGET_WIDGET_TASKS"

if [ -d "$SHORTCUTS_DIR_SRC" ]; then
    find "$SHORTCUTS_DIR_SRC" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' script_src; do
        script_name=$(basename "$script_src")
        script_target="$SHORTCUTS_DIR_TARGET_WIDGET_TASKS/$script_name"

        echo " - Processing widget shortcut: $script_name"
        chmod +x "$script_src" # Ensure source is executable

        echo "   - Copying script: $script_src -> $script_target"
        cp -f "$script_src" "$script_target"
        if [ $? -ne 0 ]; then
            echo "   - WARNING: Failed to copy script for $script_name to widget tasks directory"
        else
             chmod +x "$script_target"
        fi
    done
    echo "Termux:Widget home screen shortcuts copied to $SHORTCUTS_DIR_TARGET_WIDGET_TASKS."
    echo "NOTE: You may need to restart Termux:Widget or your launcher for changes to appear."
    echo "      Remember to add the desired shortcuts (e.g., sync-obsidian-now, sync-obsidian-resync) to your home screen manually via Android Widgets."
else
     echo "No source shortcuts directory found at $SHORTCUTS_DIR_SRC. Skipping widget shortcut setup."
fi

# --- Setup Termux:Widget Dynamic Shortcuts (Copying for App Long-Press) ---
echo "Setting up Termux:Widget dynamic shortcuts (copies)..."
mkdir -p "$DYNAMIC_SHORTCUTS_DIR_TARGET"

if [ -d "$SHORTCUTS_DIR_SRC" ]; then
    find "$SHORTCUTS_DIR_SRC" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' script_src; do
        script_name=$(basename "$script_src")
        script_target="$DYNAMIC_SHORTCUTS_DIR_TARGET/$script_name"

        echo " - Processing dynamic shortcut: $script_name"
        chmod +x "$script_src" # Ensure source is executable

        echo "   - Copying script: $script_src -> $script_target"
        cp -f "$script_src" "$script_target"
        if [ $? -ne 0 ]; then
            echo "   - WARNING: Failed to copy script for $script_name to dynamic shortcuts directory"
        else
             chmod +x "$script_target"
        fi
    done
    echo "Termux:Widget dynamic shortcuts copied."
    echo "NOTE: You might need to restart Termux or Termux:Widget for dynamic shortcuts to refresh."
else
     echo "No source shortcuts directory found at $SHORTCUTS_DIR_SRC. Skipping dynamic shortcut setup."
fi

# --- Initial Job Scheduling ---
echo "Performing initial scheduling of sync jobs..."
bash "$TERMUX_BOOT_SETUP_SCRIPT"
if [ $? -eq 0 ]; then
    echo "Initial job scheduling successful."
else
    echo "WARNING: Initial job scheduling failed. Check logs and run manually if needed: bash $TERMUX_BOOT_SETUP_SCRIPT"
fi

# --- Check Android Battery Optimizations ---
echo ""
echo "####################################################################"
echo "IMPORTANT: Android's battery optimization WILL interfere."
echo "Please go to Android Settings -> Apps -> See all apps."
echo "Find 'Termux', 'Termux:API', and 'Termux:Boot'."
echo "For EACH app, go to its 'Battery' settings and select 'Unrestricted'."
echo "Failure to do this will prevent background jobs from running reliably!"
echo "####################################################################"
echo ""

# --- Test Sync (Optional Initial Sync) ---
# Modified this section to run initial sync with --resync --verbose
read -p "Do you want to run an initial Obsidian sync now? (Recommended, uses --resync) (y/N): " run_sync_now
if [[ "$run_sync_now" =~ ^[Yy]$ ]]; then
    echo "Running initial sync with --resync --verbose..."
    echo "Log file: $STATE_DIR/sync-obsidian.log"
    # Run with --resync and --verbose flags
    bash "$YGG_CLIENT_DIR/android/scripts/sync-obsidian.sh" --resync --verbose
    sync_test_exit_code=$?
    # (Keep the exit code checking logic as before)
    if [ $sync_test_exit_code -eq 0 ] || [ $sync_test_exit_code -eq 9 ]; then
        echo "Initial sync finished (Exit code: $sync_test_exit_code). Check logs for details."
    elif [ $sync_test_exit_code -eq 124 ]; then
        echo "Initial sync TIMED OUT. Check logs: $STATE_DIR/sync-obsidian.log"
    elif [ $sync_test_exit_code -eq 7 ]; then
        echo "Initial sync FAILED (Code 7): Resync needed, but it was already attempted. Check rclone config and logs."
    else
        echo "Initial sync FAILED (Exit code: $sync_test_exit_code). Check logs for details: $STATE_DIR/sync-obsidian.log"
    fi
else
    echo "Skipping initial sync. Automatic syncs will run without --resync."
    echo "If you encounter issues later, use the 'sync-obsidian-resync' widget/shortcut."
fi

echo ""
echo "Android Sync Setup Completed!"
echo "-------------------------------------"
echo "IMPORTANT REMINDER:"
echo "Since shortcut scripts are COPIED, you MUST re-run this setup script"
echo " ( bash $YGG_CLIENT_DIR/android/scripts/setup-android-sync.sh ) "
echo "after doing a 'git pull' if any scripts in 'android/shortcuts/' were updated,"
echo "to ensure the copies in ~/.shortcuts/tasks/ and ~/.termux/widget/dynamic_shortcuts/ are updated."
echo "-------------------------------------"
echo "The Obsidian sync job is scheduled and should run periodically on Wi-Fi."
echo "The setup will be re-applied automatically on boot via Termux:Boot."
echo "Remember to disable battery optimizations!"
