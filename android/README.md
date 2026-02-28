# Yggdrasil Client - Android Sync Setup

This directory contains scripts and configuration for setting up background synchronization tasks on an Android device using Termux.

## Prerequisites

1.  **Termux:** Installed from F-Droid or GitHub (recommended).
2.  **Termux:API App:** Installed from F-Droid or GitHub.
3.  **Termux:Boot App:** Installed from F-Droid or GitHub.
4.  **Clone Repository:** Ensure this `ygg_client` repository is cloned into your Termux home directory (e.g., `~/git/ygg_client`). The scripts assume this location by default.
5.  **Termux Packages & Storage:** Run the bootstrap script located within the `android/scripts` directory *after* cloning:
    ```bash
    cd ~/git/ygg_client # Or wherever you cloned it
    bash android/scripts/bootstrap.sh
    ```
    This installs `termux-api`, `rclone`, `git`, `openssh`, and other utilities. It also runs `termux-setup-storage`. You *must* accept the storage permission request from Android when it pops up.
6.  **Optional (multi-job sync):** Build `yggsync` from the sibling repo (`~/git/yggsync`) or download a release via `bash android/scripts/fetch-yggsync.sh v0.1.3`, then run `android/scripts/install.sh` to place it in `~/.local/bin`. Configure via `android/config/ygg_sync.toml.template` -> `~/.config/ygg_sync.toml`.

## Initial Setup

1.  **Run Bootstrap:** If you haven't already, run the bootstrap script:
    ```bash
    cd ~/git/ygg_client
    bash android/scripts/bootstrap.sh
    ```
    Follow any prompts (especially for `rclone config` if needed). Grant storage permissions when asked by Android.
2.  **Run Setup Script:** Execute the main Android setup script:
    ```bash
    bash android/scripts/setup-android-sync.sh
    ```
    *   This script will:
        *   Check prerequisites (packages, storage).
        *   Verify `rclone` configuration exists (`~/.config/rclone/rclone.conf`) and optionally contains the `NAS_Obsidian` remote.
        *   Make sync scripts executable.
        *   Set up the `~/.termux/boot/` script to re-register jobs on boot.
        *   Perform the initial scheduling of the `sync-obsidian.sh` job using `termux-job-scheduler`.
        *   Remind you strongly about battery optimization settings.
        *   Optionally run an initial sync.
3.  **DISABLE BATTERY OPTIMIZATION:**
    *   This is **CRITICAL** for background tasks.
    *   Go to Android Settings -> Apps -> See all apps.
    *   Find `Termux`, `Termux:API`, and `Termux:Boot`.
    *   For **each** app, go to its `Battery` settings and select **"Unrestricted"**. If you don't do this, Android *will* kill the background sync process eventually.

## How it Works

*   **`android/scripts/bootstrap.sh`:** Installs necessary Termux packages and performs first-time setup like storage access and prompting for `rclone config`.
*   **`rclone`:** Handles the connection and synchronization with the SMB share (`smb://192.168.5.2/pi/obsidian`). Configuration is stored in `~/.config/rclone/rclone.conf`.
*   **`android/scripts/sync-obsidian.sh`:** The core script that executes `rclone bisync` between the NAS and `~/storage/shared/Documents/obsidian`. Includes locking, logging, timeout, Wi-Fi check. Accepts `--verbose` flag (to enable toasts for manual runs) and `--resync` flag (to force rclone's resync check). Automatic background runs do *not* use these flags. Detects exit code 7 and suggests manual resync if needed.
*   **`termux-job-scheduler`:** Used via `termux-boot-sync-jobs.sh` to schedule `sync-obsidian.sh` to run periodically (e.g., every hour) but *only* when on an unmetered network (typically Wi-Fi). This leverages Android's efficient JobScheduler API and is the *primary* network condition gatekeeper.
*   **`Termux:Boot`:** Runs the simple wrapper script `~/.termux/boot/ygg-start-sync-jobs` on device startup.
*   **`~/.termux/boot/ygg-start-sync-jobs`:** This small script simply calls the main job registration script (`android/scripts/termux-boot-sync-jobs.sh`) located within the git repository. This makes updates easy (just `git pull`).
*   **`android/scripts/termux-boot-sync-jobs.sh`:** Re-registers the necessary jobs with `termux-job-scheduler` after a boot, ensuring the schedule persists.
*   **`android/scripts/setup-android-sync.sh`:** Orchestrates the initial setup and configuration on the Android device. Can be re-run if needed. **It COPIES executable scripts from `android/shortcuts/` into `~/.shortcuts/tasks/` (for home screen widgets) and `~/.termux/widget/dynamic_shortcuts/` (for app long-press shortcuts).** Runs the optional *initial* sync with `--resync --verbose`.
*   **`android/shortcuts/`:** Contains scripts for Termux:Widget:
    *   `sync-obsidian-now`: Triggers a normal sync with toasts enabled (`--verbose`).
    *   `sync-obsidian-resync`: Triggers a sync forcing rclone's resync check, with toasts enabled (`--resync --verbose`). Use this if the normal sync fails with errors (especially code 7) or if you suspect sync state issues.

## Updating

1.  Pull changes from your Git repository:
    ```bash
    cd ~/git/ygg_client
    git pull
    ```
2.  Make the potentially updated scripts executable:
    ```bash
    chmod +x android/scripts/*.sh android/shortcuts/*
    ```
3.  **Re-run Setup After Updating Shortcut Scripts:** If `git pull` updated any scripts within `android/shortcuts/`, you **must** re-run the setup script to copy the new versions to the locations Termux:Widget uses:
    ```bash
    bash android/scripts/setup-android-sync.sh
    ```
    Re-run setup also if dependencies (`bootstrap.sh`), the setup process itself, or scheduling (`termux-boot-sync-jobs.sh`) were changed.

## Troubleshooting

*   **Logs:**
    *   Sync Log: `cat ~/.local/state/ygg_client/sync-obsidian.log`
    *   Boot Script Log: `cat ~/.local/state/ygg_client/termux-boot.log`
*   **Job Status:** Check scheduled jobs: `termux-job-scheduler --print` (or `-p`)
*   **Battery Optimization:** RE-VERIFY that battery optimization is disabled ("Unrestricted") for Termux, Termux:API, and Termux:Boot.
*   **Permissions:** Ensure Termux still has storage permission (`ls ~/storage/shared/Documents`). Re-run `termux-setup-storage` if needed.
*   **API Commands:** Test API commands manually (e.g., `termux-wifi-connectioninfo`, `termux-toast "Test"`). If they fail, ensure the Termux:API app is running and hasn't been killed by the system.
*   **`rclone` Config:** Test the remote connection manually: `rclone lsd NAS_Obsidian:pi/obsidian --config ~/.config/rclone/rclone.conf`
*   **Manual Sync:** Run the sync script directly to see errors: `bash ~/git/ygg_client/android/scripts/sync-obsidian.sh`
*   **Manual Job Scheduling:** Run the boot script manually: `bash ~/git/ygg_client/android/scripts/termux-boot-sync-jobs.sh`
*   **Stale Lock:** Check `sync-obsidian.log` for messages about stale locks or skipping due to existing locks. Manually remove the lock directory if necessary: `rmdir ~/.local/state/ygg_client/sync-obsidian.lock`
