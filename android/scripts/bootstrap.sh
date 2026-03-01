#!/data/data/com.termux/files/usr/bin/bash

echo "Starting Termux Bootstrap for Yggdrasil Client (Android)..."

# --- Update Packages ---
echo "Updating package lists..."
pkg update || { echo >&2 "ERROR: pkg update failed. Check network connection."; exit 1; }

# --- Install Core Dependencies ---
# Removed 'termux-boot' as it's an app, not a package.
# Added: coreutils (for timeout, tail, etc.), ncurses-utils (optional, for tput etc.)
echo "Installing required packages (termux-api, rclone, git, openssh, coreutils, ncurses-utils)..."
pkg install -y termux-api rclone git openssh coreutils ncurses-utils \
    || { echo >&2 "ERROR: Failed to install core packages. Aborting."; exit 1; }

# --- Install Optional but Useful Tools ---
# echo "Installing optional packages (curl, wget)..."
# pkg install -y curl wget

# --- Setup Storage ---
echo "Requesting Storage Access..."
echo "IMPORTANT: An Android permission popup should appear. Please grant storage access."
termux-setup-storage
# Give user time to react to the popup
sleep 5
# Check if storage seems accessible (basic check)
if [ ! -d "$HOME/storage/shared" ]; then
    echo "WARNING: ~/storage/shared directory not found. Storage permission might not have been granted."
    echo "Please ensure you granted storage permission in the Android popup."
    echo "You might need to run 'termux-setup-storage' again manually."
else
    echo "Storage access seems okay (~/storage/shared exists)."
fi

# --- Check for Termux Add-on Apps ---
echo "Checking for Termux Add-on Apps..."
echo "Please ensure you have installed the 'Termux:API' and 'Termux:Boot' apps from F-Droid or GitHub."
echo "The Play Store versions may be outdated or non-functional."
# We can't automatically install them, just remind the user.

# --- Check rclone Configuration ---
RCLONE_CONFIG_FILE="$HOME/.config/rclone/rclone.conf"
echo "Checking for existing rclone configuration ($RCLONE_CONFIG_FILE)..."
if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
    echo "rclone config file not found."
    read -p "Do you want to run 'rclone config' now to set up your NAS remote? (y/N): " run_rclone_now
    if [[ "$run_rclone_now" =~ ^[Yy]$ ]]; then
        rclone config
        # Re-check after running
        if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
            echo "WARNING: rclone config file still not found after running command."
            echo "You will need to configure it manually later for syncs to work."
        else
            echo "rclone config created at $RCLONE_CONFIG_FILE."
        fi
    else
        echo "Skipping 'rclone config'. You must configure it manually later."
    fi
else
    echo "Existing rclone config file found at $RCLONE_CONFIG_FILE."
fi

# --- Ensure basic directories exist ---
mkdir -p "$HOME/git"
mkdir -p "$HOME/.local/state/ygg_client" # For logs and locks

# --- Final Instructions ---
echo ""
echo "Termux Bootstrap Completed."
echo "-------------------------------------"
echo "Next Steps:"
echo "1. Ensure 'Termux:API' and 'Termux:Boot' apps are installed from F-Droid/GitHub."
echo "2. If you haven't already, clone the yggclient repository:"
echo "   cd ~/gh"
echo "   git clone <your-upstream-url>/yggclient.git"
echo "3. Navigate into the repository:"
echo "   cd ~/gh/yggclient"
echo "4. Run the Android setup script:"
echo "   bash android/scripts/setup-android-sync.sh"
echo "5. CRITICAL: Disable Battery Optimization for Termux, Termux:API, and Termux:Boot in Android Settings."
echo "-------------------------------------"

exit 0
