# Yggdrasil Client - Android Sync Setup

This directory contains scripts and configuration for setting up background synchronization tasks on an Android device using Termux.

## Prerequisites

1.  **Termux:** Installed from F-Droid or GitHub (recommended).
2.  **Termux:API App:** Installed from F-Droid or GitHub.
3.  **Termux:Boot App:** Installed from F-Droid or GitHub.
4.  **Clone Repository:** Ensure this `yggclient` repository is cloned into your Termux home directory (for example `~/gh/yggclient`). Scripts auto-detect their own repo root and also support `YGG_CLIENT_DIR`.
5.  **Termux Packages & Storage:** Run the bootstrap script located within the `android/scripts` directory *after* cloning:
    ```bash
    cd ~/gh/yggclient # Or wherever you cloned it
    bash android/scripts/bootstrap.sh
    ```
    This installs `termux-api`, `rclone`, `git`, `openssh`, and other utilities. It also runs `termux-setup-storage`. You *must* accept the storage permission request from Android when it pops up.
6.  **Optional (multi-job sync):** Build `yggsync` from the sibling repo (`~/gh/yggsync`) or download a release via `bash android/scripts/fetch-yggsync.sh`, then run `android/scripts/install.sh` to place it in `~/.local/bin`. Configure via `android/config/ygg_sync.toml.template` -> `~/.config/ygg_sync.toml`.

## Initial Setup

1.  **Run Bootstrap:** If you haven't already, run the bootstrap script:
    ```bash
    cd ~/gh/yggclient
    bash android/scripts/bootstrap.sh
    ```
    Follow any prompts (especially for `rclone config` if needed). Grant storage permissions when asked by Android.
2.  **Run Setup Script:** Execute the main Android setup script:
    ```bash
    bash android/scripts/setup-android-sync.sh
    ```
    *   This script will:
        *   Check prerequisites (packages, storage).
        *   Verify `rclone` configuration exists (`~/.config/rclone/rclone.conf`) and optionally contains the `smb0` remote.
        *   Make sync scripts executable.
        *   Set up the `~/.termux/boot/` script to re-register jobs on boot.
        *   Perform the initial scheduling of the `yggsync` fast/bulk jobs using `termux-job-scheduler`.
        *   Remind you strongly about battery optimization settings.
        *   Optionally run an initial sync.
3.  **DISABLE BATTERY OPTIMIZATION:**
    *   This is **CRITICAL** for background tasks.
    *   Go to Android Settings -> Apps -> See all apps.
    *   Find `Termux`, `Termux:API`, and `Termux:Boot`.
    *   For **each** app, go to its `Battery` settings and select **"Unrestricted"**. If you don't do this, Android *will* kill the background sync process eventually.

## How it Works

*   **`android/scripts/bootstrap.sh`:** Installs necessary Termux packages and performs first-time setup like storage access and prompting for `rclone config`.
*   **`rclone`:** Handles the actual file transfer work. Configuration is stored in `~/.config/rclone/rclone.conf`.
*   **`yggsync`:** The sync engine. It reads `~/.config/ygg_sync.toml`, exposes named jobs, takes a lock to stop overlaps, and provides a deliberate `--resync --force-bisync` recovery path when `bisync` safety checks trip.
*   **`android/scripts/sync-yggsync-fast.sh`:** Runs the fast notes/Obsidian job set on a calmer schedule. It checks battery state, lowers process priority, and only runs jobs that actually exist in the local `yggsync` config.
*   **`android/scripts/sync-yggsync-bulk.sh`:** Runs slower media/archive jobs such as DCIM and screenshots. It is intentionally conservative and skips work if the relevant jobs are not configured.
*   **`android/scripts/update-public-stack.sh`:** Optional boot-time updater. It fast-forwards the public `yggclient` checkout, refreshes the released `yggsync` binary, and re-copies widget shortcuts before the jobs are scheduled.
*   **`termux-job-scheduler`:** Used via `termux-boot-sync-jobs.sh` to schedule the fast and bulk `yggsync` wrappers. Both are gated on unmetered networking; both now also avoid low-battery runs.
*   **`Termux:Boot`:** Runs the simple wrapper script `~/.termux/boot/ygg-start-sync-jobs` on device startup.
*   **`~/.termux/boot/ygg-start-sync-jobs`:** This small script simply calls the main job registration script (`android/scripts/termux-boot-sync-jobs.sh`) located within the git repository. This makes updates easy (just `git pull`).
*   **`android/scripts/termux-boot-sync-jobs.sh`:** Re-registers the necessary jobs with `termux-job-scheduler` after a boot, ensuring the schedule persists.
*   **`android/scripts/setup-android-sync.sh`:** Orchestrates the initial setup and configuration on the Android device. Can be re-run if needed. **It COPIES executable scripts from `android/shortcuts/` into `~/.shortcuts/tasks/` (for home screen widgets) and `~/.termux/widget/dynamic_shortcuts/` (for app long-press shortcuts).** Runs the optional initial recovery sync through `yggsync`.
*   **`android/shortcuts/`:** Contains scripts for Termux:Widget:
    *   `sync-obsidian-resync`: Triggers a recovery sync with `--resync --force-bisync`. Use this when deletes or renames trip bisync safety checks, or when the normal sync reports a state error.
    *   `sync-yggsync-fast`: Triggers the calmer fast-job wrapper manually.
    *   `sync-yggsync-bulk`: Triggers the calmer bulk-job wrapper manually.

## Updating

1.  Pull changes from your Git repository:
    ```bash
    cd ~/gh/yggclient
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
    *   Fast Job Log: `cat ~/.local/state/ygg_client/sync-yggsync-fast.log`
    *   Bulk Job Log: `cat ~/.local/state/ygg_client/sync-yggsync-bulk.log`
    *   Boot Script Log: `cat ~/.local/state/ygg_client/termux-boot.log`
*   **Job Status:** Check scheduled jobs: `termux-job-scheduler --print` (or `-p`)
*   **Battery Optimization:** RE-VERIFY that battery optimization is disabled ("Unrestricted") for Termux, Termux:API, and Termux:Boot.
*   **Permissions:** Ensure Termux still has storage permission (`ls ~/storage/shared/Documents`). Re-run `termux-setup-storage` if needed.
*   **API Commands:** Test API commands manually (e.g., `termux-wifi-connectioninfo`, `termux-toast "Test"`). If they fail, ensure the Termux:API app is running and hasn't been killed by the system.
*   **`rclone` Config:** Test the remote connection manually: `rclone lsd smb0:data/obsidian --config ~/.config/rclone/rclone.conf`
*   **Manual Sync:** Run the calmer fast wrapper directly to see errors: `bash ~/gh/yggclient/android/scripts/sync-yggsync-fast.sh`
*   **Manual Job Scheduling:** Run the boot script manually: `bash ~/gh/yggclient/android/scripts/termux-boot-sync-jobs.sh`
*   **Stale Lock:** Check the fast/bulk logs for messages about an active lock. If the device crashed mid-run and no `yggsync` process is alive, remove the lock file from the path configured in `~/.config/ygg_sync.toml`.
