#!/data/data/com.termux/files/usr/bin/bash

echo "Starting Termux Bootstrap for Yggdrasil Client (Android)..."

# --- Update Packages ---
echo "Updating package lists..."
pkg update || { echo >&2 "ERROR: pkg update failed. Check network connection."; exit 1; }

# --- Install Core Dependencies ---
# Removed 'termux-boot' as it's an app, not a package.
# Added: coreutils (for timeout, tail, etc.), ncurses-utils (optional, for tput etc.)
echo "Installing required packages (termux-api, git, openssh, coreutils, ncurses-utils)..."
pkg install -y termux-api git openssh coreutils ncurses-utils \
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
echo "5. Set SMB credentials for yggsync, for example:"
echo "   export SAMBA_PASSWORD='your-nas-password'"
echo "6. CRITICAL: Disable Battery Optimization for Termux, Termux:API, and Termux:Boot in Android Settings."
echo "-------------------------------------"

exit 0
