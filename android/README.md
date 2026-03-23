# Yggdrasil Client - Android Sync Setup

This directory contains the Android-side Termux automation for `yggsync`.
The current stack uses native `yggsync` SMB access, not `rclone`.

## Prerequisites

1. **Termux:** Install from F-Droid or GitHub.
2. **Termux:API:** Install from F-Droid or GitHub.
3. **Termux:Boot:** Install from F-Droid or GitHub.
4. **Clone the repo:** Keep `yggclient` in your Termux home, for example `~/gh/yggclient`.
5. **Bootstrap packages and storage:**
   ```bash
   cd ~/gh/yggclient
   bash android/scripts/bootstrap.sh
   ```
6. **Install `yggsync`:**
   ```bash
   bash android/scripts/fetch-yggsync.sh
   bash android/scripts/install.sh
   ```
7. **Provide SMB credentials to Termux:**
   ```bash
   export SAMBA_PASSWORD='your-nas-password'
   ```

## Initial Setup

Run:

```bash
cd ~/gh/yggclient
bash android/scripts/setup-android-sync.sh
```

This setup script will:

- check Termux prerequisites and storage access
- create `~/.config/ygg_sync.toml` from the Android template if missing
- install the boot wrapper under `~/.termux/boot/`
- copy widget and dynamic shortcuts from `android/shortcuts/`
- register the fast and bulk jobs with `termux-job-scheduler`
- optionally run an initial Obsidian `worktree` sync

## Battery Settings

This is required.

- Open Android Settings -> Apps -> See all apps
- Set `Termux`, `Termux:API`, and `Termux:Boot` to `Battery -> Unrestricted`

Without this, Android will eventually kill the background jobs.

## How It Works

- [`android/scripts/bootstrap.sh`](/home/pi/gh/yggclient/android/scripts/bootstrap.sh): installs required Termux packages and requests storage access
- [`android/scripts/install.sh`](/home/pi/gh/yggclient/android/scripts/install.sh): installs the fetched `yggsync` binary into `~/.local/bin`
- [`android/scripts/setup-android-sync.sh`](/home/pi/gh/yggclient/android/scripts/setup-android-sync.sh): configures boot, shortcuts, and scheduling
- [`android/scripts/sync-yggsync-fast.sh`](/home/pi/gh/yggclient/android/scripts/sync-yggsync-fast.sh): runs fast notes and Obsidian jobs conservatively
- [`android/scripts/sync-yggsync-bulk.sh`](/home/pi/gh/yggclient/android/scripts/sync-yggsync-bulk.sh): runs slower media/archive jobs
- [`android/scripts/update-public-stack.sh`](/home/pi/gh/yggclient/android/scripts/update-public-stack.sh): optional boot-time repo and binary refresh
- [`android/scripts/termux-boot-sync-jobs.sh`](/home/pi/gh/yggclient/android/scripts/termux-boot-sync-jobs.sh): re-registers jobs after boot

The compatibility-named shortcut `sync-obsidian-resync` now runs native `worktree` sync.
It no longer triggers `rclone bisync` recovery flags.

## Updating

Update the checkout:

```bash
cd ~/gh/yggclient
git pull
```

If shortcut scripts changed, re-run setup so the copied widget files are refreshed:

```bash
bash android/scripts/setup-android-sync.sh
```

## Troubleshooting

- Fast job log: `cat ~/.local/state/ygg_client/sync-yggsync-fast.log`
- Bulk job log: `cat ~/.local/state/ygg_client/sync-yggsync-bulk.log`
- Boot log: `cat ~/.local/state/ygg_client/termux-boot.log`
- Job status: `termux-job-scheduler --print`
- Manual fast run: `bash ~/gh/yggclient/android/scripts/sync-yggsync-fast.sh`
- Manual boot registration: `bash ~/gh/yggclient/android/scripts/termux-boot-sync-jobs.sh`
- Stale lock: if no `yggsync` process is alive, remove the lock file configured in `~/.config/ygg_sync.toml`

If SMB auth fails, confirm that `SAMBA_PASSWORD` is exported in the Termux environment seen by the job or widget.
