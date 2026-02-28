#!/usr/bin/env bash

# Script to add a user to sudoers with passwordless sudo permissions
# Must be run as root

set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please execute with sudo:"
    echo "sudo $0"
    exit 1
fi

# Get the original user who called sudo
REAL_USER=${SUDO_USER:-}
if [[ -z "$REAL_USER" ]]; then
    echo "Could not determine the actual user. Please run this with sudo."
    exit 1
fi

# Create sudoers.d directory if it doesn't exist
mkdir -p /etc/sudoers.d

# Create the sudoers file for the user
echo "$REAL_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$REAL_USER"

# Set correct permissions
chmod 440 "/etc/sudoers.d/$REAL_USER"

echo "Successfully added $REAL_USER to sudoers with passwordless sudo access."