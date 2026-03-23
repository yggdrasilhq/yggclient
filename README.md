# yggclient

Public endpoint automation for the Yggdrasil client stack.

This repo owns the endpoint-side pieces:

- `yggsync` wrapper scripts and templates
- Android Termux install/update helpers
- desktop service and timer templates
- workstation utility scripts

Boundaries:

- `yggsync` owns the sync engine and TOML schema
- `yggdrasil` owns ISO/build logic
- `ygg-docs` owns long-form docs

What follows is the operator README for running `yggsync` through `yggclient`.

## Layout

- [`scripts/yggsync/fetch-yggsync.sh`](/home/pi/gh/yggclient/scripts/yggsync/fetch-yggsync.sh): fetch Linux `yggsync`
- [`scripts/yggsync/render-config.sh`](/home/pi/gh/yggclient/scripts/yggsync/render-config.sh): render `~/.config/ygg_sync.toml` from a template
- [`scripts/yggsync/run-desktop-yggsync.sh`](/home/pi/gh/yggclient/scripts/yggsync/run-desktop-yggsync.sh): desktop wrapper
- [`config/yggsync/desktop/ygg_sync.toml.template`](/home/pi/gh/yggclient/config/yggsync/desktop/ygg_sync.toml.template): desktop template
- [`android/config/ygg_sync.toml.template`](/home/pi/gh/yggclient/android/config/ygg_sync.toml.template): Android template
- [`android/scripts/update-public-stack.sh`](/home/pi/gh/yggclient/android/scripts/update-public-stack.sh): boot-time repo and binary refresh
- [`android/scripts/setup-android-sync.sh`](/home/pi/gh/yggclient/android/scripts/setup-android-sync.sh): Android scheduler and shortcut setup

## yggsync Quick Start

Install the binary:

```bash
bash scripts/yggsync/fetch-yggsync.sh
```

Render the desktop config:

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

## Writing yggsync Config

`yggsync` reads `~/.config/ygg_sync.toml` by default.
Start from one of the tracked templates:

- desktop: [`config/yggsync/desktop/ygg_sync.toml.template`](/home/pi/gh/yggclient/config/yggsync/desktop/ygg_sync.toml.template)
- Android: [`android/config/ygg_sync.toml.template`](/home/pi/gh/yggclient/android/config/ygg_sync.toml.template)

Important top-level keys:

- `rclone_binary`
- `rclone_config`
- `lock_file`
- `default_flags`

Each `[[jobs]]` block needs:

- `name`
- `type`
- `local`
- `remote`

Useful optional keys:

- `flags`
- `include`
- `exclude`
- `filter_rules`
- `resync_on_exit`
- `resync_flags`
- `local_retention_days`
- `timeout_seconds`

Use `filter_rules` when plain `include` and `exclude` globs are not enough.
Do not mix `filter_rules` with `include` or `exclude` in the same job.

Example Obsidian job for SMB:

```toml
[[jobs]]
name = "obsidian"
type = "bisync"
local = "~/storage/shared/Documents/obsidian"
remote = "smb0:data/smbfs/dada/obsidian"
resync_on_exit = [7]
resync_flags = ["--resync"]
filter_rules = [
  "- **/.obsidian/**",
  "- **/.trash/**",
  "- **/*.conflict*",
  "- [A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]~[A-Za-z0-9].*",
  "- **/[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]~[A-Za-z0-9].*",
]
flags = [
  "--create-empty-src-dirs",
  "--resilient",
  "--recover",
  "--conflict-loser", "pathname",
  "--max-delete", "90",
]
```

Those last filters exclude SMB DOS 8.3 aliases such as `AW5E46~3.MD`, which can otherwise poison `bisync` state on some shares.

## How yggclient Autosets It

There are two supported paths.

Environment-first:

1. Copy [`config/profiles.example.env`](/home/pi/gh/yggclient/config/profiles.example.env) to `config/profiles.local.env`.
2. Set private values there, especially `SAMBA_USER` and `SCREENCASTS_REMOTE` when needed.
3. Render the config:

```bash
bash scripts/yggsync/render-config.sh desktop
```

TOML-first:

1. Copy [`yggclient.example.toml`](/home/pi/gh/yggclient/yggclient.example.toml) to `yggclient.local.toml`.
2. Set `[sync].samba_user`, `[sync].screencasts_remote`, and other local values.
3. Generate the legacy env file:

```bash
python3 scripts/render-profile-env.py
```

4. Render the config:

```bash
bash scripts/yggsync/render-config.sh desktop
```

Desktop install flow:

- [`scripts/install/install-service.sh`](/home/pi/gh/yggclient/scripts/install/install-service.sh) now renders `~/.config/ygg_sync.toml` automatically when you install the desktop `yggsync` units and the config does not already exist.

## Android Stack

Bootstrap and install:

```bash
bash android/scripts/bootstrap.sh
bash android/scripts/fetch-yggsync.sh
bash android/scripts/setup-android-sync.sh
```

What the Android stack does:

- installs or refreshes `~/.local/bin/yggsync`
- uses the Android template at `~/.config/ygg_sync.toml`
- schedules fast and bulk jobs through `termux-job-scheduler`
- refreshes Termux widgets and dynamic shortcuts
- can auto-update the public stack on boot

The boot updater now skips fetching a new binary when the installed `yggsync` version already matches the configured target version.

## Recovery

Normal run:

```bash
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -jobs obsidian
```

Manual recovery after a bisync state failure:

```bash
~/.local/bin/yggsync -config ~/.config/ygg_sync.toml -jobs obsidian --resync --force-bisync
```

## License

Apache-2.0
