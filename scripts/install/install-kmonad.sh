#! /usr/bin/bash
# Install the kmonad binary from the upstream project's own releases.
#
# We used to serve a private mirror of the kmonad repo purely to host one build
# artifact. That mirror is gone: upstream publishes a static Linux binary on
# every release, so there is nothing for us to keep in sync and no stale fork to
# explain. Track latest by default and ride upstream; set KMONAD_VERSION to pin
# a specific tag when reproducing a machine.

set -euo pipefail

KMONAD_VERSION="${KMONAD_VERSION:-latest}"
install_location="${KMONAD_INSTALL_DIR:-${HOME}/.local/bin}"

# GitHub serves /releases/latest/download/<asset> as a redirect to the newest
# release, so tracking latest needs no API call and no token.
if [ "$KMONAD_VERSION" = "latest" ]; then
  url="https://github.com/kmonad/kmonad/releases/latest/download/kmonad"
else
  url="https://github.com/kmonad/kmonad/releases/download/${KMONAD_VERSION}/kmonad"
fi

mkdir -p "$install_location"

# Download beside the target and move into place only on success, so a failed
# fetch leaves the previously working binary alone.
tmp="$(mktemp "${install_location}/.kmonad.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

if ! wget -q --show-progress -O "$tmp" "$url"; then
  echo "error: could not download kmonad ${KMONAD_VERSION} from ${url}" >&2
  exit 1
fi

# A 404 page would download happily; an ELF header is the thing worth checking.
if [ "$(head -c 4 "$tmp" | od -An -tx1 | tr -d ' \n')" != "7f454c46" ]; then
  echo "error: downloaded file is not an ELF binary — check KMONAD_VERSION=${KMONAD_VERSION}" >&2
  exit 1
fi

chmod +x "$tmp"
mv "$tmp" "$install_location/kmonad"
trap - EXIT

echo
echo "kmonad (${KMONAD_VERSION}) downloaded from github.com/kmonad/kmonad"
echo "It is installed at $install_location/kmonad"
echo
echo "It is not required to be added in path as the systemd service"
echo "file will call the full path as $install_location/kmonad"
