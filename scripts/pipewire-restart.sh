#!/usr/bin/bash

systemctl --user restart pipewire
systemctl --user restart pipewire-session-manager
systemctl --user restart pipewire-pulse

