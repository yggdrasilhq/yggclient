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

The `sync-obsidian-resync` shortcut name is kept for compatibility, but it now runs a native `worktree` sync instead of an old `rclone bisync` recovery flow.

## Obsidian Usage

Two workflows are supported:

- direct SMB-mounted vault, if you personally keep exactly one live machine active at a time
- local vault plus `worktree` sync, if you want safer handoff semantics and explicit conflict detection

Your current direct-SMB workflow is acceptable under the first model.
The `worktree` path exists for the cases where you want less filesystem risk without giving up a central NAS repository.

## License

Apache-2.0
