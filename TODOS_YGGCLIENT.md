# TODOs - yggclient

## yggcli Interactive Setup

- [ ] Add an interactive `yggcli setup` flow for first-time endpoint bootstrap.
- [ ] Detect active shell (`bash`, `zsh`, others) and apply startup sourcing safely.
- [ ] Offer to add/update shell sourcing for `config/bashrc/index.template` with preview + confirmation.
- [ ] Create/update local profile file (`config/profiles.local.env`) from `config/profiles.example.env`.
- [ ] Provide guided prompts for private/local values and write them only to the local profile.
- [ ] Validate required binaries and dependencies (for selected features) before enabling services.
- [ ] Discover available service/timer templates and let the user select which units to install/enable.
- [ ] Render selected templates, install units, and show exact resulting `systemctl` state.
- [ ] Add a non-interactive mode (`--non-interactive` + flags) for reproducible provisioning.
- [ ] Add `yggcli config view` to inspect effective config without printing secrets by default.
- [ ] Add `yggcli config edit` to safely edit local profile values.
- [ ] Add `yggcli doctor` to verify shell sourcing, config presence, and unit health.
- [ ] Document migration path from deprecated local paths to `~/gh/yggclient`.
