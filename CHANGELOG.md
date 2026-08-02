# Changelog

This file tracks user-visible changes in `yggclient`.

## Unreleased

- Add `android/scripts/setup-sshd-service.sh`: boot-persistent, key-only Termux
  sshd for phones driven from a workstation. Operator action: run it once per
  phone, after putting the workstation key and its allowed source CIDRs in
  `~/.config/ygg_client.env` (new keys documented in
  `android/config/ygg_client.env.example`). `--persist-only` refreshes just the
  persistence layer and is safe to run over ssh on a phone already set up.
- Fix Termux phones losing ssh on every reboot. `sv-enable sshd` is not durable:
  `$PREFIX/var/service/sshd/down` is shipped by the openssh package and is not a
  dpkg conffile, so any `pkg upgrade` restores it and the phone then boots with
  sshd supervised-but-down. The setup script now installs one enforcement
  routine, `~/.local/bin/ygg-sshd-ensure`, driven from three independent
  triggers - the Termux:Boot hook, an apt post-invoke hook, and a persisted
  `termux-job-scheduler` watchdog - and logs its decisions to
  `~/.local/state/ygg_client/sshd-ensure.log`.
- Fix lego certificate renewals with lego 5.x by passing renewal flags after
  the `run` subcommand, preserving lego failures as nonzero systemd failures,
  and disabling ARI by default for migrated renewal state.
- Suppress Infisical CLI secret-value tables during certificate upload so
  private key material is not written to service logs.
