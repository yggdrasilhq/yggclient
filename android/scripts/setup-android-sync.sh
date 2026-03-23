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
command -v termux-job-scheduler >/dev/null 2>&1 || { echo >&2 "ERROR: termux-api commands not found. Run 'bash $BOOTSTRAP_SCRIPT' and ensure Termux:API app is installed/running. Aborting."; exit 1; }
command -v termux-setup-storage >/dev/null 2>&1 || { echo >&2 "ERROR: termux-setup-storage not found? Should be part of Termux base. Aborting."; exit 1; }
[ -d "$HOME/storage/shared" ] || { echo >&2 "ERROR: ~/storage/shared not found. Run 'termux-setup-storage' and grant permission via the Android popup. Aborting."; exit 1; }
[ -d "$YGG_CLIENT_DIR" ] || { echo >&2 "ERROR: Yggdrasil client directory not found at $YGG_CLIENT_DIR. Clone the repo first. Aborting."; exit 1; }
[ -f "$BOOTSTRAP_SCRIPT" ] || { echo >&2 "ERROR: Bootstrap script not found at $BOOTSTRAP_SCRIPT. Ensure repo is cloned correctly. Aborting."; exit 1; }


# --- Ensure State Directory Exists ---
mkdir -p "$STATE_DIR"
echo "State directory ensured at $STATE_DIR"

echo "Checking yggsync configuration..."
if [ ! -f "$HOME/.config/ygg_sync.toml" ]; then
    mkdir -p "$HOME/.config"
    if [ -x "$YGG_CLIENT_DIR/scripts/yggsync/render-config.sh" ]; then
        "$YGG_CLIENT_DIR/scripts/yggsync/render-config.sh" android
        echo "Rendered ~/.config/ygg_sync.toml from the Android template."
    else
        cp "$YGG_CLIENT_DIR/android/config/ygg_sync.toml.template" "$HOME/.config/ygg_sync.toml"
        echo "Created ~/.config/ygg_sync.toml from the Android template."
    fi
fi
echo "Ensure your SMB credentials are available to Termux, for example:"
echo "  export SAMBA_PASSWORD='your-nas-password'"

# --- Make core scripts executable ---
echo "Making core scripts executable..."
chmod +x "$YGG_CLIENT_DIR/android/scripts/"*.sh # Make all scripts in android/scripts executable
chmod +x "$TERMUX_BOOT_SETUP_SCRIPT"
chmod +x "$BOOTSTRAP_SCRIPT" # Ensure bootstrap is executable too

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
    echo "      Remember to add the desired shortcuts (e.g., sync-obsidian-resync, sync-yggsync-fast) to your home screen manually via Android Widgets."
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
read -p "Do you want to run an initial Obsidian sync now? (Recommended, uses native worktree sync) (y/N): " run_sync_now
if [[ "$run_sync_now" =~ ^[Yy]$ ]]; then
    echo "Running initial yggsync worktree sync..."
    echo "Log file: $STATE_DIR/sync-yggsync-fast.log"
    JOBS="obsidian,notes" bash "$YGG_CLIENT_DIR/android/shortcuts/sync-obsidian-resync"
    sync_test_exit_code=$?
    if [ $sync_test_exit_code -eq 0 ]; then
        echo "Initial sync finished (Exit code: $sync_test_exit_code). Check logs for details."
    else
        echo "Initial sync FAILED (Exit code: $sync_test_exit_code). Check logs for details: $STATE_DIR/sync-yggsync-fast.log"
    fi
else
    echo "Skipping initial sync. Automatic syncs will run in the calmer scheduled mode."
    echo "If you want a manual Obsidian run later, use the 'sync-obsidian-resync' widget/shortcut."
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
echo "The yggsync fast and bulk jobs are scheduled and should run periodically on unmetered network."
echo "The setup will be re-applied automatically on boot via Termux:Boot."
echo "Remember to disable battery optimizations!"
