# Yggdrasil Client - Android Sync Setup

This directory contains the Android-side Termux automation for `yggsync`.
The current stack uses a Go `yggsync` wrapper for policy, scheduling, notifications, and SMB uploads.
`yggsync-core` remains as the worktree engine for notes/Obsidian jobs.

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
   # Optional: fetch the legacy worktree engine if you do not already have it.
   bash android/scripts/fetch-yggsync.sh

   # Copy/build the wrapper binary into android/bin/yggsync, then install:
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
- create `~/.config/yggsync.runtime.toml` from the runtime template if missing
- install the boot wrapper under `~/.termux/boot/`
- copy widget and dynamic shortcuts from `android/shortcuts/`
- register the obsidian and bulk jobs through `yggsync android install-jobs`
- optionally run an initial Obsidian `worktree` sync

## Battery Settings

This is required.

- Open Android Settings -> Apps -> See all apps
- Set `Termux`, `Termux:API`, and `Termux:Boot` to `Battery -> Unrestricted`

Without this, Android will eventually kill the background jobs.

## How It Works

- [`android/scripts/bootstrap.sh`](/home/user/gh/yggclient/android/scripts/bootstrap.sh): installs required Termux packages and requests storage access
- [`android/scripts/install.sh`](/home/user/gh/yggclient/android/scripts/install.sh): installs the wrapper/core binaries, boot hook, and shortcuts
- [`android/scripts/setup-android-sync.sh`](/home/user/gh/yggclient/android/scripts/setup-android-sync.sh): configures boot, shortcuts, and scheduling
- [`android/scripts/fetch-yggsync.sh`](/home/user/gh/yggclient/android/scripts/fetch-yggsync.sh): fetches the legacy `yggsync-core` build when needed
- [`android/scripts/update-public-stack.sh`](/home/user/gh/yggclient/android/scripts/update-public-stack.sh): optional boot-time repo and binary refresh
- [`android/scripts/termux-boot-sync-jobs.sh`](/home/user/gh/yggclient/android/scripts/termux-boot-sync-jobs.sh): re-registers jobs after boot via `yggsync`

Obsidian is now a first-class `yggsync` command/profile rather than being hidden inside the generic `fast` lane.
The compatibility-named shortcut `sync-obsidian-resync` uses that dedicated command.
Bulk uploads now default to a `500 MiB` cellular cap per run. Use the `sync-yggsync-bulk-force` shortcut only when you explicitly want to override that protection for one run.

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

- Obsidian job log: `cat ~/.local/state/yggsync/obsidian.log`
- Bulk job log: `cat ~/.local/state/yggsync/bulk.log`
- Manual shortcut logs: `cat ~/.local/state/yggsync/manual-obsidian.log`, `cat ~/.local/state/yggsync/manual-bulk.log`, and `cat ~/.local/state/yggsync/manual-bulk-force.log`
- Boot log: `cat ~/.local/state/ygg_client/termux-boot.log`
- Job status: `termux-job-scheduler --print`
- Manual Obsidian run: `bash ~/gh/yggclient/android/shortcuts/sync-obsidian-resync`
- Manual boot registration: `bash ~/gh/yggclient/android/scripts/termux-boot-sync-jobs.sh`
- Stale lock: if no `yggsync` process is alive, remove the lock file configured in `~/.config/ygg_sync.toml`

If SMB auth fails, confirm that `SAMBA_PASSWORD` is exported in the Termux environment seen by the job or widget.
