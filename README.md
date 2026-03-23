# yggclient

Client-side automation for Yggdrasil endpoints.

This repo owns:

- `yggsync` fetch/render/install wrappers
- Android Termux setup, schedulers, and shortcuts
- desktop service/timer installation helpers
- workstation utility scripts

Boundaries:

- `yggsync` owns the sync engine and TOML schema
- `yggdrasil` owns ISO/build logic
- `ygg-docs` owns long-form documentation

This README is the operator guide for running `yggsync` through `yggclient`.

If you are not comfortable setting this up from scratch, use the sections below as the minimum operator checklist.
The intent is that you only edit a few variables, render the config, and then run known commands.

## Layout

- [`scripts/yggsync/fetch-yggsync.sh`](/home/pi/gh/yggclient/scripts/yggsync/fetch-yggsync.sh): fetch Linux `yggsync`
- [`scripts/yggsync/render-config.sh`](/home/pi/gh/yggclient/scripts/yggsync/render-config.sh): render `~/.config/ygg_sync.toml`
- [`scripts/yggsync/run-desktop-yggsync.sh`](/home/pi/gh/yggclient/scripts/yggsync/run-desktop-yggsync.sh): desktop wrapper
- [`config/yggsync/desktop/ygg_sync.toml.template`](/home/pi/gh/yggclient/config/yggsync/desktop/ygg_sync.toml.template): desktop template
- [`android/config/ygg_sync.toml.template`](/home/pi/gh/yggclient/android/config/ygg_sync.toml.template): Android template
- [`android/scripts/setup-android-sync.sh`](/home/pi/gh/yggclient/android/scripts/setup-android-sync.sh): Android scheduler and shortcut setup
- [`android/scripts/update-public-stack.sh`](/home/pi/gh/yggclient/android/scripts/update-public-stack.sh): boot-time refresh

## Quick Start

Install the binary:

```bash
bash scripts/yggsync/fetch-yggsync.sh
```

Render a desktop config:

```bash
bash scripts/yggsync/render-config.sh desktop
```

List jobs:

```bash
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -list
```

Dry-run selected jobs:

```bash
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -jobs screenshots-desktop,screencasts -dry-run
```

## The Minimum You Need To Edit

For most setups, you do not need to hand-edit every job.
You usually only need to set these values:

- `SAMBA_HOST`: NAS hostname or IP
- `SAMBA_SHARE`: SMB share name, usually `data`
- `SAMBA_USER`: path owner used in remote paths, for example `dada`
- `SAMBA_USERNAME`: SMB login account, for example `datauser`
- `SAMBA_PASSWORD_ENV`: usually `SAMBA_PASSWORD`
- `SCREENCASTS_REMOTE`: only if the default screencast path is wrong for that machine

Important distinction:

- `SAMBA_USERNAME` is the SMB login name
- `SAMBA_USER` is the username embedded in remote paths

On your phone, for example, that means:

```bash
SAMBA_HOST=192.168.0.213
SAMBA_SHARE=data
SAMBA_USER=dada
SAMBA_USERNAME=datauser
SAMBA_PASSWORD_ENV=SAMBA_PASSWORD
```

If `SAMBA_USERNAME` and `SAMBA_USER` are the same for your machine, set both to the same value.

## Config Model

`yggsync` now syncs directly to local paths and SMB shares.
There is no `rclone` dependency in the main stack.

Tracked templates:

- desktop: [`config/yggsync/desktop/ygg_sync.toml.template`](/home/pi/gh/yggclient/config/yggsync/desktop/ygg_sync.toml.template)
- Android: [`android/config/ygg_sync.toml.template`](/home/pi/gh/yggclient/android/config/ygg_sync.toml.template)

Important top-level keys:

- `lock_file`
- `worktree_state_dir`
- `[[targets]]`
- `[[jobs]]`

Each `[[targets]]` block defines a named backend. For SMB:

```toml
[[targets]]
name = "nas"
type = "smb"
host = "nas.lan"
share = "data"
username = "alice"
password_env = "SAMBA_PASSWORD"
```

Each `[[jobs]]` block needs:

- `name`
- `type`
- `local`
- `remote`

Supported job types:

- `copy`
- `sync`
- `retained_copy`
- `worktree`

Use `worktree` for a local Obsidian vault that syncs against a central SMB repository in an `SVN`-like model.
Use direct SMB-mounted vaults only when you are deliberately operating with one live machine at a time.

Example Android Obsidian job:

```toml
[[jobs]]
name = "obsidian"
type = "worktree"
local = "~/storage/shared/Documents/obsidian"
remote = "nas:smbfs/dada/obsidian"
filter_rules = [
  "- **/.obsidian/**",
  "- **/.trash/**",
  "- **/*.conflict*",
  "- [A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_]~[A-Za-z0-9].*",
  "- **/[A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_][A-Za-z0-9_]~[A-Za-z0-9].*",
]
```

Those last filters exclude DOS 8.3 alias names exposed by some SMB shares.

## How To Set It Up Yourself

There are two supported ways to drive config rendering.

### Option 1: Environment-First

Use this if you want a simple shell file with the values you change per machine.

1. Copy [`config/profiles.example.env`](/home/pi/gh/yggclient/config/profiles.example.env) to `config/profiles.local.env`
2. Edit:
   - `SAMBA_HOST`
   - `SAMBA_SHARE`
   - `SAMBA_USER`
   - `SAMBA_USERNAME`
   - `SAMBA_PASSWORD_ENV`
   - `SCREENCASTS_REMOTE` if needed
3. Render:

```bash
bash scripts/yggsync/render-config.sh desktop
```

For Android:

```bash
bash scripts/yggsync/render-config.sh android
```

### Option 2: TOML-First

Use this if you want one local machine profile in TOML and let `yggclient` derive the shell env file from it.

1. Copy [`yggclient.example.toml`](/home/pi/gh/yggclient/yggclient.example.toml) to `yggclient.local.toml`
2. Edit the `[sync]` section:
   - `samba_host`
   - `samba_share`
   - `samba_user`
   - `samba_username`
   - `samba_password_env`
   - `screencasts_remote` if needed
3. Generate the env file:

```bash
python3 scripts/render-profile-env.py
```

4. Render the real `yggsync` config:

```bash
bash scripts/yggsync/render-config.sh desktop
```

## What The Templates Already Decide For You

The tracked templates already encode the job layout.
In normal use you should not need to edit every job block unless you are changing your NAS directory structure.

The desktop template already sets:

- screenshot upload path
- screencast upload path
- download archive filters
- flatpak backup paths

The Android template already sets:

- Obsidian as a `worktree` job
- WhatsApp database and media upload jobs
- DCIM retained upload
- screenshot retained upload
- Cube Call Recorder retained upload
- `androidfs` catch-all archive exclusions

If those remote directories are right for you, only the SMB login/path variables need changing.

## How yggclient Autosets It

Environment-first flow:

1. Copy [`config/profiles.example.env`](/home/pi/gh/yggclient/config/profiles.example.env) to `config/profiles.local.env`.
2. Set `SAMBA_HOST`, `SAMBA_SHARE`, `SAMBA_USER`, and `SCREENCASTS_REMOTE`.
   If the SMB login name differs from the path-owner name, also set `SAMBA_USERNAME`.
3. Render the config:

```bash
bash scripts/yggsync/render-config.sh desktop
```

TOML-first flow:

1. Copy [`yggclient.example.toml`](/home/pi/gh/yggclient/yggclient.example.toml) to `yggclient.local.toml`.
2. Set `[sync].samba_host`, `[sync].samba_share`, `[sync].samba_user`, and related values.
   Set `[sync].samba_username` too if SMB auth uses a different account name.
3. Generate the compatibility env file:

```bash
python3 scripts/render-profile-env.py
```

4. Render the config:

```bash
bash scripts/yggsync/render-config.sh desktop
```

The desktop installer at [`scripts/install/install-service.sh`](/home/pi/gh/yggclient/scripts/install/install-service.sh) will render `~/.config/ygg_sync.toml` automatically when the desktop units are installed and the file does not already exist.

## Commands You Will Actually Run

Desktop:

```bash
# Fetch binary
bash scripts/yggsync/fetch-yggsync.sh

# Render config
bash scripts/yggsync/render-config.sh desktop

# Inspect jobs
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -list

# Dry-run a small job
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -jobs screenshots-desktop -dry-run
```

Android in Termux:

```bash
# Bootstrap Termux
bash android/scripts/bootstrap.sh

# Fetch the Android binary
bash android/scripts/fetch-yggsync.sh

# Install/update the local stack
bash android/scripts/install.sh
bash android/scripts/setup-android-sync.sh
```

Manual Obsidian commands:

```bash
# Pull the central NAS vault into local phone storage
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -jobs obsidian -worktree-op update

# Push local vault state to the NAS
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -jobs obsidian -worktree-op commit

# Merge non-conflicting changes after the worktree already exists
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -jobs obsidian -worktree-op sync
```

## Android Stack

Bootstrap and install:

```bash
bash android/scripts/bootstrap.sh
bash android/scripts/fetch-yggsync.sh
bash android/scripts/setup-android-sync.sh
```

What the Android stack does:

- installs or refreshes `~/.local/bin/yggsync`
- copies the Android template to `~/.config/ygg_sync.toml` if needed
- schedules fast and bulk jobs through `termux-job-scheduler`
- refreshes Termux widget and dynamic shortcut copies
- can refresh the public checkout and `yggsync` release binary on boot

For native SMB jobs, ensure Termux has your NAS password in the environment, for example:

```bash
export SAMBA_PASSWORD='your-nas-password'
```

If you need a one-off local bootstrap, you can also place `password = "..."` in the rendered Android config, but `password_env` is the preferred steady-state setup.

The `sync-obsidian-resync` shortcut name is kept for compatibility, but it now runs a native `worktree` sync instead of an old `rclone bisync` recovery flow.

## Obsidian Usage

Two workflows are supported:

- direct SMB-mounted vault, if you personally keep exactly one live machine active at a time
- local vault plus `worktree` sync, if you want safer handoff semantics and explicit conflict detection

Your current direct-SMB workflow is acceptable under the first model.
The `worktree` path exists for the cases where you want less filesystem risk without giving up a central NAS repository.

## Setup Checklist

Use this checklist if you are doing the setup yourself:

1. Set the SMB variables in `config/profiles.local.env` or `yggclient.local.toml`
2. Render `~/.config/ygg_sync.toml`
3. Open the rendered config once and confirm:
   - `host`
   - `share`
   - `username`
   - remote paths containing the correct `${SAMBA_USER}`-derived layout
4. Export `SAMBA_PASSWORD` if you use `password_env`
5. Run `~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -list`
6. Run one small `-dry-run` job
7. For Obsidian `worktree`, do the first initialization with `-worktree-op update` or `-worktree-op commit`
8. Only then rely on widgets, scheduled jobs, or systemd units

## License

Apache-2.0
