#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

echo "Starting Yggdrasil Client Android Sync Setup..."

# --- Variables ---
SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_CLIENT_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_CLIENT_DIR="${YGG_CLIENT_DIR:-$YGG_CLIENT_DIR_DEFAULT}"
STATE_DIR="$HOME/.local/state/ygg_client"
BOOTSTRAP_SCRIPT="$YGG_CLIENT_DIR/android/scripts/bootstrap.sh"
INSTALL_SCRIPT="$YGG_CLIENT_DIR/android/scripts/install.sh"
CONFIG_TEMPLATE="$YGG_CLIENT_DIR/android/config/ygg_sync.toml.template"
RUNTIME_TEMPLATE="$YGG_CLIENT_DIR/android/config/yggsync.runtime.toml.template"
CONFIG_PATH="${YGG_SYNC_CONFIG:-$HOME/.config/ygg_sync.toml}"
RUNTIME_PATH="${YGG_SYNC_RUNTIME:-$HOME/.config/yggsync.runtime.toml}"

# --- Prerequisites Check ---
echo "Checking prerequisites..."
command -v termux-job-scheduler >/dev/null 2>&1 || { echo >&2 "ERROR: termux-api commands not found. Run 'bash $BOOTSTRAP_SCRIPT' and ensure Termux:API app is installed/running. Aborting."; exit 1; }
command -v termux-setup-storage >/dev/null 2>&1 || { echo >&2 "ERROR: termux-setup-storage not found? Should be part of Termux base. Aborting."; exit 1; }
[ -d "$HOME/storage/shared" ] || { echo >&2 "ERROR: ~/storage/shared not found. Run 'termux-setup-storage' and grant permission via the Android popup. Aborting."; exit 1; }
[ -d "$YGG_CLIENT_DIR" ] || { echo >&2 "ERROR: Yggdrasil client directory not found at $YGG_CLIENT_DIR. Clone the repo first. Aborting."; exit 1; }
[ -f "$BOOTSTRAP_SCRIPT" ] || { echo >&2 "ERROR: Bootstrap script not found at $BOOTSTRAP_SCRIPT. Ensure repo is cloned correctly. Aborting."; exit 1; }
[ -f "$INSTALL_SCRIPT" ] || { echo >&2 "ERROR: Install script not found at $INSTALL_SCRIPT. Ensure repo is cloned correctly. Aborting."; exit 1; }

# --- Ensure State Directory Exists ---
mkdir -p "$STATE_DIR"
echo "State directory ensured at $STATE_DIR"

echo "Checking yggsync configuration..."
mkdir -p "$HOME/.config"
if [ ! -f "$CONFIG_PATH" ]; then
    mkdir -p "$HOME/.config"
    if [ -x "$YGG_CLIENT_DIR/scripts/yggsync/render-config.sh" ]; then
        "$YGG_CLIENT_DIR/scripts/yggsync/render-config.sh" android
        echo "Rendered $CONFIG_PATH from the Android template."
    else
        cp "$CONFIG_TEMPLATE" "$CONFIG_PATH"
        echo "Created $CONFIG_PATH from the Android template."
    fi
fi
if [ ! -f "$RUNTIME_PATH" ]; then
    cp "$RUNTIME_TEMPLATE" "$RUNTIME_PATH"
    echo "Created $RUNTIME_PATH from the Android runtime template."
fi

echo "Ensure your SMB credentials are available to Termux, for example:"
echo "  export SAMBA_PASSWORD='your-nas-password'"

echo "Installing Android-side boot hooks, shortcuts, and jobs..."
bash "$INSTALL_SCRIPT"

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
    echo "Log file: $HOME/.local/state/yggsync/manual-obsidian.log"
    JOBS="obsidian" bash "$YGG_CLIENT_DIR/android/shortcuts/sync-obsidian-resync"
    sync_test_exit_code=$?
    if [ $sync_test_exit_code -eq 0 ]; then
        echo "Initial sync finished (Exit code: $sync_test_exit_code). Check logs for details."
    else
        echo "Initial sync FAILED (Exit code: $sync_test_exit_code). Check logs for details: $HOME/.local/state/yggsync/manual-obsidian.log"
    fi
else
    echo "Skipping initial sync. Automatic syncs will run in the calmer scheduled mode."
    echo "If you want a manual Obsidian run later, use the 'sync-obsidian-resync' widget/shortcut."
fi

echo ""
echo "Android Sync Setup Completed!"
echo "-------------------------------------"
echo "Re-run 'bash $YGG_CLIENT_DIR/android/scripts/install.sh' after a yggclient update"
echo "to refresh the copied boot/shortcut scripts."
echo "The yggsync obsidian and bulk jobs are scheduled by 'yggsync android install-jobs'."
echo "The setup will be re-applied automatically on boot via Termux:Boot."
echo "Remember to disable battery optimizations!"
