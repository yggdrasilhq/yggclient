# yggclient

Public upstream for Yggdrasil endpoint automation.

This repository contains portable client-side assets for Linux and Android endpoints:
- sync tooling
- systemd service/timer templates
- endpoint install helpers
- workstation utility scripts

## Scope and Boundaries

- `yggclient`: executable scripts/templates and minimal operational notes.
- `yggdrasil`: build/ISO logic.
- `ygg-docs`: user/developer documentation.

## Public/Private Separation

`yggclient` replaces the private predecessor `git/ygg_client` as the active upstream.

To keep this repository public-safe:
- keep infrastructure-specific values in `config/profiles.local.env` (gitignored)
- keep `config/profiles.example.env` generalized
- do not commit private hosts, domains, or tokens

## Local Profiles

1. Copy the example profile:
   ```bash
   cp config/profiles.example.env config/profiles.local.env
   ```
2. Set private values in `config/profiles.local.env`.
3. Source `config/bashrc/index.template` from your shell startup.

## License

Apache-2.0
