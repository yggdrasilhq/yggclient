# yggclient

Public upstream for Yggdrasil endpoint automation.

This repository is the portable client layer for Linux and Android endpoints in the Yggdrasil ecosystem:
- sync tooling
- systemd service/timer templates
- endpoint install helpers
- workstation utility scripts

## Scope

- `yggclient`: executable assets and minimal operational notes only.
- `yggdrasil`: build/ISO logic.
- `ygg-docs`: user/developer documentation.

## Public/Private Separation

This repository replaces the private predecessor (`ygg_client`) as the active upstream.

Design rule:
- generalized defaults stay in versioned files
- private infrastructure values stay local and unversioned

Use:
- `config/profiles.example.env` for shareable defaults
- `config/profiles.local.env` for machine/user secrets and private endpoints (gitignored)

Never commit private hosts, tokens, or environment-specific secrets.

## Local Setup

1. Create your local profile:
   ```bash
   cp config/profiles.example.env config/profiles.local.env
   ```
2. Set private values in `config/profiles.local.env`.
3. Source the shell integration from your startup file:
   ```bash
   source "$HOME/git/yggclient/config/bashrc/index.template"
   ```

## Migration From `ygg_client`

1. Switch shell sourcing from `~/git/ygg_client` to `~/git/yggclient`.
2. Move private Infisical/profile values into `config/profiles.local.env`.
3. Reinstall currently used `ygg-*` units from templates in this repo so installed unit files reference the new repository path.
4. Verify no active unit file references `~/git/ygg_client`.

## License

Apache-2.0
