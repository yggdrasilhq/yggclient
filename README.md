# ygg-client

Client-side tooling for Yggdrasil systems (desktop/laptop endpoints, sync helpers, local automation).

## Repository Policy

- This is the public source of truth for client scripts/templates.
- Private predecessor: `git/ygg_client` (deprecated for active feature work).

## Documentation

All documentation is centralized in `ygg-docs`.

## Local Profiles

- tracked template: `config/profiles.example.env`
- local file: `config/profiles.local.env` (gitignored)

`profiles.local.env` is intended to reproduce private legacy infrastructure behavior
without committing private host/domain details to the public tree.

## License

Apache-2.0
