# Changelog

This file tracks user-visible changes in `yggclient`.

## Unreleased

- Fix lego certificate renewals with lego 5.x by passing renewal flags after
  the `run` subcommand, preserving lego failures as nonzero systemd failures,
  and disabling ARI by default for migrated renewal state.
