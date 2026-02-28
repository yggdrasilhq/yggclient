#!/usr/bin/env bash

set -euo pipefail

# Disconnect Wuzhi Audio from a remote host and connect it locally.

choose_default_remote_host() {
    # Pick the opposite host between 192.168.0.138 and 192.168.0.144.
    local local_ip
    local_ip=$(hostname -I | tr ' ' '\n' | grep '^192\.168\.0\.' | head -n1)

    case "$local_ip" in
    192.168.0.138)
        echo "pi@192.168.0.144"
        ;;
    192.168.0.144)
        echo "pi@192.168.0.138"
        ;;
    *)
        echo "pi@192.168.0.144"
        ;;
    esac
}

REMOTE_HOST="${REMOTE_HOST:-$(choose_default_remote_host)}"
DEVICE_MAC="${DEVICE_MAC:-EA:82:FE:43:D4:05}"
DEVICE_NAME="${DEVICE_NAME:-Wuzhi Audio}"

echo "Disconnecting ${DEVICE_NAME} (${DEVICE_MAC}) on ${REMOTE_HOST}..."
if ! ssh "${REMOTE_HOST}" "bluetoothctl disconnect ${DEVICE_MAC}"; then
    echo "Warning: remote disconnect failed (device may already be disconnected)." >&2
fi

echo "Connecting ${DEVICE_NAME} locally..."
bluetoothctl connect "${DEVICE_MAC}"

echo "Current status on this host:"
bluetoothctl info "${DEVICE_MAC}" | grep -E "^(Name|Alias|Connected|RSSI)"
