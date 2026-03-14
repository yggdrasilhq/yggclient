# AGENTS

## Mission

Maintain client-side automation for Yggdrasil endpoints (Linux and Android):

- sync tooling
- service templates
- endpoint install helpers
- workstation-level utility scripts

## Boundaries

- Build/ISO logic belongs in `yggdrasil`.
- User/developer docs belong in `ygg-docs`.
- This repo should contain executable scripts/templates and minimal operational notes.

## Local Profiles

Use `config/profiles.local.env` (gitignored) to inject private infrastructure values.
Keep `config/profiles.example.env` generalized.
The TOML source of truth for new tooling is `yggclient.local.toml` (gitignored), with
`python3 scripts/render-profile-env.py` generating the shell profile used by legacy scripts.
